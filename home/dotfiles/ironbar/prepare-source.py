"""Apply small, version-checked UI fixes to the pinned Ironbar source at build time."""
from pathlib import Path


def replace(file, old, new):
    path = Path(file)
    source = path.read_text()
    if source.count(old) != 1:
        raise RuntimeError(f"Ironbar source changed: {file}: {old[:80]!r}")
    path.write_text(source.replace(old, new))


replace("Cargo.toml", 'gtk-layer-shell = "0.8.2"',
        'gtk-layer-shell = { version = "0.8.2", features = ["v0_6"] }')

# Popups contain password fields: moving the pointer must not dismiss them.
path = Path("src/popup.rs")
source = path.read_text()
start = source.index("        let leave_timeout = rc_mut!")
end = source.index("        let output_size = rc_mut!", start)
source = source[:start] + '''        win.set_keyboard_mode(gtk_layer_shell::KeyboardMode::OnDemand);
        win.connect_key_press_event(|win, event| {
            if event.keyval() == gtk::gdk::keys::constants::Escape {
                win.hide();
                Propagation::Stop
            } else {
                Propagation::Proceed
            }
        });
        let focus_timeout = rc_mut!(None::<glib::SourceId>);
        let focus_epoch = Rc::new(std::cell::Cell::new(0u64));
        let focused_since_map = Rc::new(std::cell::Cell::new(false));
        {
            let focus_timeout = focus_timeout.clone();
            let focus_epoch = focus_epoch.clone();
            let focused_since_map = focused_since_map.clone();
            win.connect_focus_out_event(move |win, _| {
                // On-demand popups can be mapped without receiving keyboard focus.
                // Ignore a delayed focus-out from a previously hidden invocation.
                if !win.is_visible() || !focused_since_map.get() {
                    return Propagation::Proceed;
                }
                if let Some(id) = focus_timeout.borrow_mut().take() { id.remove(); }
                let win = win.clone();
                let pending = focus_timeout.clone();
                let epoch = focus_epoch.get();
                let focus_epoch = focus_epoch.clone();
                *focus_timeout.borrow_mut() = Some(glib::timeout_add_local(
                    std::time::Duration::from_millis(120),
                    move || {
                        if focus_epoch.get() != epoch || !win.is_visible() {
                            *pending.borrow_mut() = None;
                            return glib::ControlFlow::Break;
                        }
                        let inside = win.display().default_seat().and_then(|seat| seat.pointer())
                            .and_then(|pointer| pointer.window_at_position().0)
                            .is_some_and(|under| Some(under.toplevel()) == win.window());
                        if !win.is_active() && !inside && gtk::grab_get_current().is_some() {
                            return glib::ControlFlow::Continue;
                        }
                        *pending.borrow_mut() = None;
                        if !win.is_active() && !inside { win.hide(); }
                        glib::ControlFlow::Break
                    },
                ));
                Propagation::Proceed
            });
        }
        {
            let focus_timeout = focus_timeout.clone();
            let focused_since_map = focused_since_map.clone();
            win.connect_focus_in_event(move |win, _| {
                if win.is_visible() { focused_since_map.set(true); }
                if let Some(id) = focus_timeout.borrow_mut().take() { id.remove(); }
                Propagation::Proceed
            });
        }
        {
            let focus_timeout = focus_timeout.clone();
            let focus_epoch = focus_epoch.clone();
            let focused_since_map = focused_since_map.clone();
            win.connect_show(move |_| {
                focus_epoch.set(focus_epoch.get().wrapping_add(1));
                focused_since_map.set(false);
                if let Some(id) = focus_timeout.borrow_mut().take() { id.remove(); }
            });
        }
        win.connect_hide(move |_| {
            focus_epoch.set(focus_epoch.get().wrapping_add(1));
            focused_since_map.set(false);
            if let Some(id) = focus_timeout.borrow_mut().take() { id.remove(); }
        });

''' + source[end:]
path.write_text(source.replace("use std::time::Duration;\n", ""))

# Reposition from the final window allocation, not a child's resize callback:
# the latter still sees the previous dropdown's width when changing modules.
replace("src/popup.rs", "        let output_size = rc_mut!(output_size);",
        '''        let output_size = rc_mut!(output_size);
        let button_cache = rc_mut!(Vec::<Button>::new());
        let current_widget = rc_mut!(None::<(usize, usize)>);
        {
            let buttons = button_cache.clone();
            let current = current_widget.clone();
            let size = output_size.clone();
            win.connect_size_allocate(move |win, _| {
                if win.is_visible() && let Some((_, button_id)) = *current.borrow() {
                    Self::set_position(&buttons.borrow(), button_id, orientation, win, &size);
                }
            });
        }
        {
            let current = current_widget.clone();
            win.connect_hide(move |_| { *current.borrow_mut() = None; });
        }''')
replace("src/popup.rs", "            button_cache: rc_mut!(vec![]),", "            button_cache,")
replace("src/popup.rs", "            current_widget: rc_mut!(None),", "            current_widget,")
replace("src/popup.rs", '''        for button in &content.buttons {
            button.ensure_popup_id();
        }''', '''        for button in &content.buttons {
            button.ensure_popup_id();
            let button_id = button.popup_id();
            let current = self.current_widget.clone();
            let buttons = self.button_cache.clone();
            let output_size = self.output_size.clone();
            let window = self.window.clone();
            let orientation = self.pos.orientation();
            button.connect_size_allocate(move |_, _| {
                if window.is_visible()
                    && current.borrow().is_some_and(|(_, active)| active == button_id)
                {
                    Self::set_position(&buttons.borrow(), button_id, orientation, &window, &output_size);
                }
            });
        }''')
replace("src/popup.rs", '''        let orientation = self.pos.orientation();
        let window = self.window.clone();

        let current_widget = self.current_widget.clone();
        let cache = self.container_cache.clone();
        let button_cache = self.button_cache.clone();

        let output_size = self.output_size.clone();

        content
            .container
            .connect_size_allocate(move |container, rect| {
                if container.is_visible() {
                    trace!("Resized:  {}x{}", rect.width(), rect.height());

                    if let Some((widget_id, button_id)) = *current_widget.borrow()
                        && let Some(PopupCacheValue { .. }) = cache.borrow().get(&widget_id)
                    {
                        Self::set_position(
                            &button_cache.borrow(),
                            button_id,
                            orientation,
                            &window,
                            &output_size,
                        );
                    }
                }
            });

''', "")
replace("src/popup.rs", "use tracing::{debug, trace};", "use tracing::debug;")
replace("src/popup.rs", '''    pub fn show(&self, widget_id: usize, button_id: usize) {
        self.clear_window();''', '''    pub fn show(&self, widget_id: usize, button_id: usize) {
        self.window.hide();
        self.clear_window();''')
replace("src/popup.rs", '''            *self.current_widget.borrow_mut() = Some((widget_id, button_id));

            content.container.add_class("popup");
            self.window.add(&content.container);

            self.window.show();''', '''            *self.current_widget.borrow_mut() = Some((widget_id, button_id));

            content.container.add_class("popup");
            self.window.add(&content.container);
            self.window.resize(
                content.container.preferred_width().1,
                content.container.preferred_height().1,
            );

            self.window.show();''')
replace("src/popup.rs", "        let (popup_width, popup_height) = window.size();",
        '''        let allocation = window.allocation();
        let (popup_width, popup_height) = (allocation.width(), allocation.height());''')
replace("src/popup.rs", '''        let widget_center = f64::from(geometry.position) + f64::from(geometry.size) / 2.0;

        let bar_offset = (f64::from(screen_size) - f64::from(geometry.bar_size)) / 2.0;

        let mut offset = bar_offset + (widget_center - (f64::from(popup_size) / 2.0)).round();

        if offset < 5.0 {
            offset = 5.0;
        } else if offset > f64::from(screen_size - popup_size) - 5.0 {
            offset = f64::from(screen_size - popup_size) - 5.0;
        }''', "        let offset = popup_offset(geometry, screen_size, popup_size);")
replace("src/popup.rs", "        window.set_layer_shell_margin(edge, offset as i32);",
        "        window.set_layer_shell_margin(edge, offset);")
path = Path("src/popup.rs")
path.write_text(path.read_text() + '''

fn popup_offset(geometry: WidgetGeometry, screen_size: i32, popup_size: i32) -> i32 {
    let center = f64::from(geometry.position) + f64::from(geometry.size) / 2.0;
    let bar_offset = (f64::from(screen_size) - f64::from(geometry.bar_size)) / 2.0;
    let offset = (bar_offset + center - f64::from(popup_size) / 2.0).round() as i32;
    let maximum = screen_size.saturating_sub(popup_size).saturating_sub(5).max(5);
    offset.clamp(5, maximum)
}

#[cfg(test)]
mod positioning_tests {
    use super::*;

    #[test]
    fn centers_beneath_a_compact_bar_button() {
        let button = WidgetGeometry { position: 120, size: 28, bar_size: 300 };
        assert_eq!(popup_offset(button, 1920, 346), 771);
    }

    #[test]
    fn clamps_full_width_bar_buttons_to_screen_edges() {
        let left = WidgetGeometry { position: 0, size: 28, bar_size: 1920 };
        let right = WidgetGeometry { position: 1892, ..left };
        assert_eq!(popup_offset(left, 1920, 346), 5);
        assert_eq!(popup_offset(right, 1920, 346), 1569);
    }

    #[test]
    fn resizing_keeps_the_same_button_center() {
        let button = WidgetGeometry { position: 120, size: 28, bar_size: 300 };
        assert_eq!(popup_offset(button, 1920, 346) + 173, 944);
        assert_eq!(popup_offset(button, 1920, 366) + 183, 944);
    }

    #[test]
    fn oversized_popup_never_gets_a_negative_margin() {
        let button = WidgetGeometry { position: 120, size: 28, bar_size: 300 };
        assert_eq!(popup_offset(button, 320, 366), 5);
    }
}
''')
replace("src/bar.rs",
        "Self::pointer_over_window(&popup_window) || gtk::grab_get_current().is_some()",
        "popup_window.is_visible() || gtk::grab_get_current().is_some()")

# Match the invisible activation strip to the bar, including tray expansion.
# Show the content before measuring it, without mapping a start-hidden window.
replace("src/bar.rs", "        let load_result = self.load_modules(config, monitor, self.monitor_size);",
        '''        let anchor_to_edges = config.anchor_to_edges;
        let load_result = self.load_modules(config, monitor, self.monitor_size);
        self.show(false);''')
replace("src/bar.rs", '''                &load_result.popup.window,
                monitor,
                autohide,''', '''                &load_result.popup.window,
                &self.content,
                self.position.orientation(),
                anchor_to_edges,
                monitor,
                autohide,''')
replace("src/bar.rs", '''        popup_window: &ApplicationWindow,
        monitor: &Monitor,
        timeout: u64,''', '''        popup_window: &ApplicationWindow,
        content: &gtk::Box,
        orientation: Orientation,
        anchor_to_edges: bool,
        monitor: &Monitor,
        timeout: u64,''')
replace("src/bar.rs", '''        // A real child gives the hotspot a full-width input region, not GTK's
        // default childless-window width. Three pixels tolerate near-edge entry.
        let hotspot = gtk::EventBox::new();
        hotspot.set_size_request(monitor.geometry().width(), 3);
        hotspot_window.add(&hotspot);
        hotspot.show();''', '''        // The hotspot shares the bar's anchors/margins, but only its long axis.
        // Never intercept pointer events on the unused portions of the edge.
        let hotspot = gtk::EventBox::new();
        hotspot_window.add(&hotspot);
        hotspot.show();
        let update_hotspot = {
            let hotspot_window = hotspot_window.clone();
            let hotspot = hotspot.clone();
            let monitor = monitor.clone();
            let previous = rc_mut!((0, 0));
            Rc::new(move |bar_length: i32| {
                let geometry = monitor.geometry();
                let limit = match orientation {
                    Orientation::Horizontal => geometry.width(),
                    _ => geometry.height(),
                };
                let size = autohide_hotspot_size(orientation, bar_length, limit);
                if *previous.borrow() != size {
                    *previous.borrow_mut() = size;
                    hotspot.set_size_request(size.0, size.1);
                    // A size request alone cannot shrink a previously wider window.
                    hotspot_window.resize(size.0, size.1);
                }
            })
        };
        let measure_length = {
            let content = content.clone();
            let monitor = monitor.clone();
            Rc::new(move || match (orientation, anchor_to_edges) {
                (Orientation::Horizontal, true) => monitor.geometry().width(),
                (Orientation::Horizontal, false) => content.preferred_width().1,
                (_, true) => monitor.geometry().height(),
                (_, false) => content.preferred_height().1,
            })
        };
        update_hotspot(measure_length());
        {
            let update_hotspot = update_hotspot.clone();
            content.connect_size_allocate(move |_, allocation| {
                let length = match orientation {
                    Orientation::Horizontal => allocation.width(),
                    _ => allocation.height(),
                };
                update_hotspot(length);
            });
        }
        {
            let update_hotspot = update_hotspot.clone();
            let measure_length = measure_length.clone();
            window.connect_show(move |_| update_hotspot(measure_length()));
        }
        {
            // Hidden windows receive no allocations when async labels/tray items
            // change. Remeasure only while the hotspot is mapped, then stop.
            let resize_timeout = rc_mut!(None::<glib::SourceId>);
            let pending = resize_timeout.clone();
            let update_hotspot = update_hotspot.clone();
            let measure_length = measure_length.clone();
            hotspot_window.connect_show(move |_| {
                if let Some(id) = pending.borrow_mut().take() { id.remove(); }
                update_hotspot(measure_length());
                let update_hotspot = update_hotspot.clone();
                let measure_length = measure_length.clone();
                *pending.borrow_mut() = Some(glib::timeout_add_local(
                    Duration::from_millis(150),
                    move || {
                        update_hotspot(measure_length());
                        glib::ControlFlow::Continue
                    },
                ));
            });
            hotspot_window.connect_hide(move |_| {
                if let Some(id) = resize_timeout.borrow_mut().take() { id.remove(); }
            });
        }
        monitor.connect_geometry_notify(move |_| update_hotspot(measure_length()));''')
path = Path("src/bar.rs")
path.write_text(path.read_text() + '''

fn autohide_hotspot_size(orientation: Orientation, bar_length: i32, limit: i32) -> (i32, i32) {
    let length = bar_length.clamp(1, limit.max(1));
    match orientation {
        Orientation::Horizontal => (length, 3),
        _ => (3, length),
    }
}

#[cfg(test)]
mod autohide_tests {
    use super::*;

    #[test]
    fn horizontal_hotspot_matches_the_centered_strip_not_the_monitor() {
        assert_eq!(autohide_hotspot_size(Orientation::Horizontal, 282, 1920), (282, 3));
    }

    #[test]
    fn vertical_hotspot_uses_the_bars_height() {
        assert_eq!(autohide_hotspot_size(Orientation::Vertical, 300, 1200), (3, 300));
    }

    #[test]
    fn expanded_and_collapsed_tray_sizes_are_not_cached() {
        assert_eq!(autohide_hotspot_size(Orientation::Horizontal, 330, 1920), (330, 3));
        assert_eq!(autohide_hotspot_size(Orientation::Horizontal, 282, 1920), (282, 3));
    }

    #[test]
    fn invalid_or_oversized_dimensions_stay_within_the_monitor() {
        assert_eq!(autohide_hotspot_size(Orientation::Horizontal, 2000, 1920), (1920, 3));
        assert_eq!(autohide_hotspot_size(Orientation::Vertical, 0, 1200), (3, 1));
        assert_eq!(autohide_hotspot_size(Orientation::Horizontal, 0, 0), (1, 3));
    }
}
''')

# Schedule hiding on reveal as well as on a real bar leave, even if the pointer
# moves away before the newly mapped panel receives its first enter event.
path = Path("src/bar.rs")
source = path.read_text()
start = source.index("        {\n            let hotspot_window = hotspot_window.clone();\n            let timeout_id = timeout_id.clone();")
end = source.index("        {\n            let timeout_id = timeout_id.clone();\n            let hotspot_window = hotspot_window.clone();\n            window.connect_destroy", start)
source = source[:start] + '''        let schedule_hide = {
            let hotspot_window = hotspot_window.clone();
            let timeout_id = timeout_id.clone();
            let popup_window = popup_window.clone();
            Rc::new(move |win: &ApplicationWindow| {
                if let Some(id) = timeout_id.borrow_mut().take() { id.remove(); }
                let win = win.clone();
                let hotspot_window = hotspot_window.clone();
                let popup_window = popup_window.clone();
                let pending = timeout_id.clone();
                *timeout_id.borrow_mut() = Some(glib::timeout_add_local(
                    Duration::from_millis(timeout.max(1)),
                    move || {
                        if Self::pointer_over_window(&win) {
                            *pending.borrow_mut() = None;
                            return glib::ControlFlow::Break;
                        }
                        if popup_window.is_visible() || gtk::grab_get_current().is_some() {
                            return glib::ControlFlow::Continue;
                        }
                        win.hide();
                        hotspot_window.show();
                        *pending.borrow_mut() = None;
                        glib::ControlFlow::Break
                    },
                ));
            })
        };
        {
            let schedule_hide = schedule_hide.clone();
            window.connect_leave_notify_event(move |win, _| {
                schedule_hide(win);
                Propagation::Proceed
            });
        }

''' + source[end:]
path.write_text(source)
replace("src/bar.rs", '''                hotspot_win.hide();
                win.show();''', '''                hotspot_win.hide();
                win.show();
                schedule_hide(&win);''')

# Match the compact spacing when additional tray icons are expanded.
replace("src/modules/tray/mod.rs", "let container = gtk::Box::new(orientation, 17);",
        "let container = gtk::Box::new(orientation, 6);")

# Keep the mixer compact and use horizontal sliders.
replace("src/modules/volume.rs",
        "let container = gtk::Box::new(Orientation::Horizontal, 10);",
        "let container = gtk::Box::new(Orientation::Vertical, 12);")
replace("src/modules/volume.rs",
        ".orientation(Orientation::Vertical)\n            .height_request(100)\n            .inverted(true)",
        ".orientation(Orientation::Horizontal)\n            .width_request(290)")

# PulseAudio notifications update widgets without sending those same values
# back to the server. During a drag, the cursor owns the slider's value.
replace("src/modules/volume.rs", "use std::collections::HashMap;",
        "use std::collections::HashMap;\nuse std::cell::Cell;\nuse std::rc::Rc;\nuse glib::Propagation;")
replace("src/modules/volume.rs", "        let container = gtk::Box::new(Orientation::Vertical, 12);",
        "        let syncing = Rc::new(Cell::new(false));\n        let container = gtk::Box::new(Orientation::Vertical, 12);")
replace("src/modules/volume.rs", '''            let tx = context.controller_tx.clone();
            sink_selector.connect_changed(move |selector| {
                if let Some(name) = selector.active_id() {''', '''            let tx = context.controller_tx.clone();
            let syncing = syncing.clone();
            sink_selector.connect_changed(move |selector| {
                if !syncing.get() && let Some(name) = selector.active_id() {''')
replace("src/modules/volume.rs", '\n        slider.add_class("slider");\n',
        '\n        slider.add_class("slider");\n        track_slider_drag(&slider);\n')
replace("src/modules/volume.rs", '''            let selector = sink_selector.clone();

            slider.connect_value_changed(move |scale| {
                if let Some(sink) = selector.active_id() {''', '''            let selector = sink_selector.clone();
            let syncing = syncing.clone();

            slider.connect_value_changed(move |scale| {
                if !syncing.get() && let Some(sink) = selector.active_id() {''')
replace("src/modules/volume.rs", '''            let selector = sink_selector.clone();

            btn_mute.connect_toggled(move |btn| {
                if let Some(sink) = selector.active_id() {''', '''            let selector = sink_selector.clone();
            let syncing = syncing.clone();

            btn_mute.connect_toggled(move |btn| {
                if !syncing.get() && let Some(sink) = selector.active_id() {''')
replace("src/modules/volume.rs", '''            .recv_glib(&input_container, move |input_container, event| {
                match event {''', '''            .recv_glib(&input_container, move |input_container, event| {
                syncing.set(true);
                match event {''')
replace("src/modules/volume.rs", '''                        slider.add_class("slider");

                        {
                            let tx = context.controller_tx.clone();
                            slider.connect_value_changed(move |scale| {''', '''                        slider.add_class("slider");
                        track_slider_drag(&slider);

                        {
                            let tx = context.controller_tx.clone();
                            let syncing = syncing.clone();
                            slider.connect_value_changed(move |scale| {
                                if syncing.get() { return; }''')
replace("src/modules/volume.rs", '''                            let tx = context.controller_tx.clone();
                            btn_mute.connect_toggled(move |btn| {''', '''                            let tx = context.controller_tx.clone();
                            let syncing = syncing.clone();
                            btn_mute.connect_toggled(move |btn| {
                                if syncing.get() { return; }''')
replace("src/modules/volume.rs", '''                            ui.slider.set_sensitive(info.can_set_volume);
                            ui.btn_mute.set_label''', '''                            ui.slider.set_sensitive(info.can_set_volume);
                            ui.btn_mute.set_active(info.muted);
                            ui.btn_mute.set_label''')
replace("src/modules/volume.rs", '''                }
            });

        Some(container)''', '''                }
                syncing.set(false);
            });

        Some(container)''')
path = Path("src/modules/volume.rs")
path.write_text(path.read_text() + '''

fn track_slider_drag(slider: &Scale) {
    slider.set_digits(0);
    slider.connect_format_value(|_, value| format!("{value:.0}%"));
    slider.connect_button_press_event(|scale, event| {
        if event.button() == 1 { scale.add_class("dragging"); }
        Propagation::Proceed
    });
    slider.connect_button_release_event(|scale, _| {
        scale.remove_class("dragging");
        Propagation::Proceed
    });
    slider.connect_grab_broken_event(|scale, _| {
        scale.remove_class("dragging");
        Propagation::Proceed
    });
    slider.connect_unmap(|scale| scale.remove_class("dragging"));
}
''')

# Bluetooth discovery runs only while its dropdown is open, and errors are visible.
replace("src/modules/bluetooth/mod.rs", "    Disable,\n", "    Disable,\n    Discover(bool),\n")
replace("src/modules/bluetooth/mod.rs",
        "                    BluetoothAction::Disable => client.disable(),",
        "                    BluetoothAction::Disable => client.disable(),\n                    BluetoothAction::Discover(active) => client.discover(active),")
replace("src/modules/bluetooth/mod.rs",
        "match devices.iter().next() {",
        "match devices.iter().find(|device| device.status == BluetoothDeviceStatus::Connected) {")
replace("src/modules/bluetooth/mod.rs",
        "        let devices = ScrolledWindow::new(gtk::Adjustment::NONE, gtk::Adjustment::NONE);",
        '''        let scan_label = Label::new(Some("Scanning for nearby devices…"));
        scan_label.add_class("status-message");
        container.add(&scan_label);
        let discovery_tx = context.controller_tx.clone();
        container.connect_map(move |_| { discovery_tx.send_spawn(BluetoothAction::Discover(true)); });
        let discovery_tx = context.controller_tx.clone();
        container.connect_unmap(move |_| { discovery_tx.send_spawn(BluetoothAction::Discover(false)); });
        let devices = ScrolledWindow::new(gtk::Adjustment::NONE, gtk::Adjustment::NONE);
        devices.set_min_content_height(60);
        devices.set_max_content_height(700);
        devices.set_propagate_natural_height(true);''')
replace("src/modules/bluetooth/mod.rs",
        "                devices.set_visible(state.is_enabled());",
        "                devices.set_visible(state.is_enabled());\n                scan_label.set_visible(state.is_enabled());")
replace("src/clients/bluetooth.rs",
        "    _rx: watch::Receiver<BluetoothState>,",
        "    _rx: watch::Receiver<BluetoothState>,\n    discovering: watch::Sender<bool>,")
replace("src/clients/bluetooth.rs",
        "        Ok(Self { session, tx, _rx })",
        '''        let (discovering, mut discovery_rx) = watch::channel(false);
        let discovery_session = session.clone();
        spawn(async move {
            loop {
                if !*discovery_rx.borrow_and_update() && discovery_rx.changed().await.is_err() {
                    break;
                }
                if !*discovery_rx.borrow_and_update() { continue; }
                let result = async {
                    let adapter = discovery_session.default_adapter().await?;
                    adapter.set_discovery_filter(bluer::DiscoveryFilter {
                        transport: bluer::DiscoveryTransport::Auto,
                        ..Default::default()
                    }).await?;
                    adapter.discover_devices().await
                }.await;
                match result {
                    Ok(mut stream) => {
                        // Dropping the stream stops only this client's discovery.
                        loop {
                            tokio::select! {
                                result = discovery_rx.changed() => {
                                    if result.is_err() { return; }
                                    break;
                                },
                                item = futures_lite::StreamExt::next(&mut stream) => {
                                    if item.is_none() { break; }
                                },
                            }
                        }
                    },
                    Err(_) => {
                        tokio::select! {
                            _ = tokio::time::sleep(Duration::from_secs(2)) => {},
                            result = discovery_rx.changed() => if result.is_err() { break; },
                        }
                    },
                }
            }
        });
        Ok(Self { session, tx, _rx, discovering })''')
replace("src/clients/bluetooth.rs",
        "    pub(crate) fn enable(&self) {",
        '''    pub(crate) fn discover(&self, active: bool) {
        self.discovering.send_replace(active);
    }

    fn report_error(message: &str) {
        let _ = std::process::Command::new("notify-send")
            .args(["--urgency=normal", "Bluetooth", message]).spawn();
    }

    pub(crate) fn enable(&self) {''')
replace("src/clients/bluetooth.rs",
        '                error!("Failed to enable: {}", err);',
        '                error!("Failed to enable: {}", err);\n                Self::report_error(&format!("Could not enable Bluetooth: {err}"));')
replace("src/clients/bluetooth.rs",
        '                error!("Connection error: {}", err);',
        '                error!("Connection error: {}", err);\n                Self::report_error(&format!("Could not connect the device: {err}"));')
replace("src/clients/bluetooth.rs",
        '                error!("Disconnect error: {}", err);',
        '                error!("Disconnect error: {}", err);\n                Self::report_error(&format!("Could not disconnect the device: {err}"));')
replace("src/clients/bluetooth.rs",
        "        adapter.set_powered(val).await?;",
        '''        if val {
            let _ = tokio::process::Command::new("rfkill").args(["unblock", "bluetooth"]).status().await;
        }
        // rfkill unblock can itself trigger BlueZ's power-on transition.
        // Wait for that transition instead of reporting a spurious Busy error.
        for attempt in 0..10 {
            if adapter.is_powered().await? == val { return Ok(()); }
            match adapter.set_powered(val).await {
                Ok(()) => return Ok(()),
                Err(error) if attempt == 9 => return Err(error.into()),
                Err(_) => tokio::time::sleep(Duration::from_millis(200)).await,
            }
        }''')
replace("src/clients/bluetooth.rs",
        "        device.connect().await?;",
        '''        if !device.is_paired().await? {
            // The existing Blueman agent handles PIN/confirmation graphically.
            device.pair().await?;
        }
        device.set_trusted(true).await?;
        device.connect().await?;''')
