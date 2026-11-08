//! Wi-Fi controls embedded in Ironbar's own anchored popup.
//! nmcli talks to the existing NetworkManager; secrets are sent through stdin.
use crate::channels::{AsyncSenderExt, BroadcastReceiverExt};
use crate::config::CommonConfig;
use crate::gtk_helpers::IronbarGtkExt;
use crate::modules::{Module, ModuleInfo, ModuleParts, ModulePopup, ModuleUpdateEvent, PopupButton, WidgetContext};
use crate::{module_impl, spawn};
use color_eyre::{eyre::eyre, Result};
use gtk::prelude::*;
use gtk::{Button, Entry, Label, Orientation, ScrolledWindow};
use serde::Deserialize;
use std::cell::RefCell;
use std::process::Stdio;
use std::rc::Rc;
use std::time::Duration;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use tokio::sync::mpsc;

#[derive(Debug, Deserialize, Clone)]
pub struct NetworkManagerModule {
    #[serde(flatten)]
    pub common: Option<CommonConfig>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Network {
    active: bool,
    ssid: String,
    bssid: String,
    strength: u8,
    security: String,
    interface: String,
}

#[derive(Debug, Clone, Default)]
pub struct State {
    enabled: bool,
    networks: Vec<Network>,
    interfaces: Vec<String>,
    message: String,
    busy: bool,
}

pub enum Action {
    Refresh(bool),
    Visible(bool),
    Radio(bool),
    Connect(Network, String),
    Disconnect(String),
}

fn fields(line: &str) -> Vec<String> {
    let mut result = vec![String::new()];
    let mut escaped = false;
    for c in line.chars() {
        if escaped {
            result.last_mut().unwrap().push(c);
            escaped = false;
        } else if c == '\\' {
            escaped = true;
        } else if c == ':' {
            result.push(String::new());
        } else {
            result.last_mut().unwrap().push(c);
        }
    }
    if escaped { result.last_mut().unwrap().push('\\'); }
    result
}

async fn nmcli(args: &[&str], password: Option<&str>) -> Result<String> {
    let mut child = Command::new("nmcli")
        .args(["--colors", "no", "--wait", "25"])
        .args(args)
        .env("LC_ALL", "C")
        .stdin(if password.is_some() { Stdio::piped() } else { Stdio::null() })
        .stdout(Stdio::piped()).stderr(Stdio::piped())
        .kill_on_drop(true).spawn()?;
    if let Some(password) = password {
        let mut stdin = child.stdin.take().ok_or_else(|| eyre!("Could not send the password"))?;
        stdin.write_all(password.as_bytes()).await?;
        stdin.write_all(b"\n").await?;
    }
    let output = tokio::time::timeout(Duration::from_secs(30), child.wait_with_output()).await??;
    if !output.status.success() {
        // Never include stdout: interactive prompts can contain secret input.
        let mut error = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if let Some(secret) = password.filter(|value| !value.is_empty()) {
            error = error.replace(secret, "••••••••");
        }
        return Err(eyre!(if error.is_empty() { "NetworkManager: operation did not complete".into() } else { error }));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

async fn snapshot() -> Result<State> {
    let enabled = nmcli(&["radio", "wifi"], None).await? == "enabled";
    let devices = nmcli(&["-t", "-f", "DEVICE,TYPE", "device", "status"], None).await?;
    let interfaces = devices.lines().filter_map(|line| {
        let values = fields(line);
        (values.len() == 2 && values[1] == "wifi").then(|| values[0].clone())
    }).collect();
    let listing = nmcli(&["-t", "-f", "IN-USE,SSID,BSSID,SIGNAL,SECURITY,DEVICE", "device", "wifi", "list", "--rescan", "no"], None).await?;
    let mut networks = Vec::new();
    for line in listing.lines() {
        let values = fields(line);
        if values.len() != 6 || values[1].is_empty() { continue; }
        networks.push(Network {
            active: values[0] == "*", ssid: values[1].clone(), bssid: values[2].clone(),
            strength: values[3].parse().unwrap_or_default(), security: values[4].clone(),
            interface: values[5].clone(),
        });
    }
    networks.sort_by_key(|network| (std::cmp::Reverse(network.active), std::cmp::Reverse(network.strength)));
    // Prefer the active/strongest AP for each SSID on each adapter.
    let mut seen = std::collections::HashSet::new();
    networks.retain(|network| seen.insert((network.ssid.clone(), network.interface.clone(), network.security.clone())));
    Ok(State { enabled, networks, interfaces, ..State::default() })
}

impl Module<Button> for NetworkManagerModule {
    type SendMessage = State;
    type ReceiveMessage = Action;
    module_impl!("network_manager");

    fn spawn_controller(&self, _: &ModuleInfo, context: &WidgetContext<State, Action>, mut rx: mpsc::Receiver<Action>) -> Result<()> {
        let tx = context.tx.clone();
        spawn(async move {
            let mut state = State::default();
            let mut visible = false;
            let mut interval = tokio::time::interval(Duration::from_secs(10));
            loop {
                let action = tokio::select! {
                    action = rx.recv() => match action { Some(action) => action, None => break },
                    _ = interval.tick() => Action::Refresh(false),
                };
                let result = match action {
                    Action::Visible(value) => {
                        visible = value;
                        if !visible { continue; }
                        state.message.clear();
                        Ok(())
                    },
                    Action::Refresh(scan) => {
                        if scan {
                            state.busy = true;
                            state.message = "Scanning for networks…".into();
                            tx.send_update(state.clone()).await;
                            nmcli(&["device", "wifi", "rescan"], None).await.map(|_| ())
                        } else { Ok(()) }
                    },
                    Action::Radio(enabled) => {
                        state.busy = true;
                        tx.send_update(state.clone()).await;
                        nmcli(&["radio", "wifi", if enabled { "on" } else { "off" }], None).await.map(|_| ())
                    },
                    Action::Connect(network, password) => {
                        state.busy = true;
                        state.message = format!("Connecting to {}…", network.ssid);
                        tx.send_update(state.clone()).await;
                        nmcli(&["--ask", "device", "wifi", "connect", &network.bssid, "ifname", &network.interface], Some(&password)).await.map(|_| ())
                    },
                    Action::Disconnect(interface) => {
                        state.busy = true;
                        tx.send_update(state.clone()).await;
                        nmcli(&["device", "disconnect", &interface], None).await.map(|_| ())
                    },
                };
                let message = match result {
                    Ok(()) if state.busy => String::new(),
                    Ok(()) => state.message.clone(),
                    Err(error) => error.to_string(),
                };
                match snapshot().await {
                    Ok(new_state) => state = new_state,
                    Err(error) => { state.busy = false; state.message = error.to_string(); tx.send_update(state.clone()).await; continue; },
                }
                state.message = message;
                // Keep the indicator current even when the popup is closed.
                if !visible { state.message.clear(); }
                tx.send_update(state.clone()).await;
            }
        });
        Ok(())
    }

    fn into_widget(self, context: WidgetContext<State, Action>, info: &ModuleInfo) -> Result<ModuleParts<Button>> {
        let button = Button::with_label("󰤮");
        let tx = context.tx.clone();
        button.connect_clicked(move |button| { tx.send_spawn(ModuleUpdateEvent::TogglePopup(button.popup_id())); });
        let indicator = button.clone();
        context.subscribe().recv_glib((), move |(), state: State| {
            let active = state.networks.iter().find(|network| network.active);
            let (icon, tooltip) = match active {
                Some(network) => {
                    let icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"];
                    (icons[usize::from(network.strength.min(100)) * 4 / 100], format!("{} · {}%", network.ssid, network.strength))
                },
                None => ("󰤮", if state.enabled { "Wi-Fi: disconnected" } else { "Wi-Fi disabled" }.into()),
            };
            indicator.set_label(icon);
            indicator.set_tooltip_text(Some(&tooltip));
        });
        let popup = self.into_popup(context, info).into_popup_parts(vec![&button]);
        Ok(ModuleParts::new(button, popup))
    }

    fn into_popup(self, context: WidgetContext<State, Action>, _: &ModuleInfo) -> Option<gtk::Box> {
        let root = gtk::Box::new(Orientation::Vertical, 10);
        root.set_width_request(340);
        let header = gtk::Box::new(Orientation::Horizontal, 10);
        let title = Label::new(Some("Wi-Fi"));
        title.add_class("popup-title");
        title.set_hexpand(true);
        title.set_xalign(0.0);
        let radio = gtk::Switch::new();
        radio.set_valign(gtk::Align::Center);
        header.add(&title);
        header.add(&radio);
        root.add(&header);

        let scan = Button::with_label("󰑐  Refresh networks");
        root.add(&scan);
        let list = gtk::Box::new(Orientation::Vertical, 4);
        let scroll = ScrolledWindow::new(gtk::Adjustment::NONE, gtk::Adjustment::NONE);
        scroll.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
        scroll.set_min_content_height(80);
        scroll.set_max_content_height(700);
        scroll.set_propagate_natural_height(true);
        scroll.add(&list);
        root.add(&scroll);

        let form = gtk::Box::new(Orientation::Vertical, 8);
        let selected_label = Label::new(None);
        selected_label.set_xalign(0.0);
        selected_label.set_ellipsize(gtk::pango::EllipsizeMode::End);
        let password = Entry::new();
        password.set_visibility(false);
        password.set_input_purpose(gtk::InputPurpose::Password);
        password.set_placeholder_text(Some("Password (leave empty if saved)"));
        let connect = Button::with_label("Connect");
        form.add(&selected_label);
        form.add(&password);
        form.add(&connect);
        root.add(&form);
        let status = Label::new(None);
        status.set_line_wrap(true);
        status.set_line_wrap_mode(gtk::pango::WrapMode::WordChar);
        status.set_max_width_chars(43);
        status.set_xalign(0.0);
        status.add_class("status-message");
        root.add(&status);

        let selected = Rc::new(RefCell::new(None::<Network>));
        let changing = Rc::new(std::cell::Cell::new(false));
        let tx = context.controller_tx.clone();
        let guard = changing.clone();
        radio.connect_state_set(move |_, enabled| {
            if !guard.get() { tx.send_spawn(Action::Radio(enabled)); }
            glib::Propagation::Proceed
        });
        let tx = context.controller_tx.clone();
        scan.connect_clicked(move |_| { tx.send_spawn(Action::Refresh(true)); });
        let tx = context.controller_tx.clone();
        let selection = selected.clone();
        let secret = password.clone();
        connect.connect_clicked(move |_| {
            if let Some(network) = selection.borrow().as_ref() {
                tx.send_spawn(Action::Connect(network.clone(), secret.text().to_string()));
                secret.set_text("");
            }
        });
        let submit = connect.clone();
        password.connect_activate(move |_| { submit.emit_clicked(); });
        let tx = context.controller_tx.clone();
        root.connect_map(move |_| { tx.send_spawn(Action::Visible(true)); });
        let tx = context.controller_tx.clone();
        let secret = password.clone();
        root.connect_unmap(move |_| { secret.set_text(""); tx.send_spawn(Action::Visible(false)); });

        root.show_all();
        form.set_no_show_all(true);
        form.hide();
        let tx = context.controller_tx.clone();
        let mut previous = None;
        context.subscribe().recv_glib((), move |(), state: State| {
            changing.set(true);
            radio.set_active(state.enabled);
            changing.set(false);
            radio.set_sensitive(!state.busy && !state.interfaces.is_empty());
            scan.set_sensitive(state.enabled && !state.busy);
            connect.set_sensitive(!state.busy);
            list.set_sensitive(!state.busy);
            status.set_text(if !state.message.is_empty() { &state.message }
                else if state.interfaces.is_empty() { "No Wi-Fi adapter found" }
                else if !state.enabled { "Wi-Fi disabled" }
                else if state.networks.is_empty() { "No networks found. Click \"Refresh networks\"." }
                else { "" });
            if selected.borrow().as_ref().is_some_and(|network| state.networks.iter().any(|item| item.active && item.bssid == network.bssid)) || !state.enabled {
                form.hide();
                selected.borrow_mut().take();
                password.set_text("");
            }
            if previous.as_ref() == Some(&state.networks) { return; }
            previous = Some(state.networks.clone());
            for child in list.children() { list.remove(&child); }
            for network in state.networks {
                let security = if network.security.is_empty() || network.security == "--" { "" } else { " " };
                let row = Button::new();
                let label = Label::new(Some(&format!("{} {}{} · {}%", if network.active { "" } else { "󰤨" }, network.ssid, security, network.strength)));
                label.set_xalign(0.0);
                label.set_ellipsize(gtk::pango::EllipsizeMode::End);
                label.set_max_width_chars(38);
                row.add(&label);
                row.set_tooltip_text(Some(if network.active { "Click to disconnect" } else { &network.security }));
                if network.active { row.add_class("connected"); }
                let tx = tx.clone();
                let selection = selected.clone();
                let form = form.clone();
                let password = password.clone();
                let selected_label = selected_label.clone();
                row.connect_clicked(move |_| {
                    if network.active { tx.send_spawn(Action::Disconnect(network.interface.clone())); }
                    else {
                        selected_label.set_text(&network.ssid);
                        password.set_text("");
                        password.set_visible(!network.security.is_empty() && network.security != "--");
                        *selection.borrow_mut() = Some(network.clone());
                        form.show();
                        password.grab_focus();
                    }
                });
                list.add(&row);
            }
            list.show_all();
        });
        Some(root)
    }
}

#[cfg(test)]
mod tests {
    use super::fields;
    #[test]
    fn nmcli_escaped_names_do_not_shift_columns() {
        assert_eq!(fields(r"*:Cafe\: west\\up:40\:3F\:8C:77:WPA2:wlan0"), vec!["*", "Cafe: west\\up", "40:3F:8C", "77", "WPA2", "wlan0"]);
        assert_eq!(fields("::"), vec!["", "", ""]);
    }
}
