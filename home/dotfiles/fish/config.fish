set -g fish_greeting

set -gx STARSHIP_CONFIG "$HOME/.config/themes/current/starship.toml"

function __load_fish_theme
  set -l theme_file "$HOME/.config/themes/current/theme.fish"
  if test -r "$theme_file"
    source "$theme_file"
  end
end

function __reload_fish_theme --on-variable __theme_reload_ts
  __load_fish_theme
end

__load_fish_theme
