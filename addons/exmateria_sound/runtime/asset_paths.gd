## Resolve asset paths without baking in any user-specific path.
##
## Resolution order:
##   1. `EXMATERIA_ASSETS_DIR` env var (points at an extracted disc tree).
##   2. Standard exmateria assets dir (populated by `exmateria-extract`):
##        Linux/BSD: $XDG_DATA_HOME/exmateria/assets/
##                   (fallback ~/.local/share/exmateria/assets/)
##        macOS:     ~/Library/Application Support/exmateria/assets/
##        Windows:   %APPDATA%\exmateria\assets
##   3. Walk up from the project root looking for project-assets/fft-extract/
##      (monorepo development layout).
##
## Published unchanged because no machine-specific paths.

class_name AssetPaths


static func standard_assets_dir() -> String:
    var os_name := OS.get_name()
    if os_name == "Windows":
        var appdata := OS.get_environment("APPDATA")
        if appdata != "":
            return appdata.path_join("exmateria").path_join("assets")
        var userprofile := OS.get_environment("USERPROFILE")
        if userprofile != "":
            return userprofile.path_join("AppData/Roaming/exmateria/assets")
        return ""
    if os_name == "macOS":
        var home_mac := OS.get_environment("HOME")
        if home_mac != "":
            return home_mac.path_join("Library/Application Support/exmateria/assets")
        return ""
    # Linux / BSD: XDG.
    var xdg := OS.get_environment("XDG_DATA_HOME")
    if xdg != "":
        return xdg.path_join("exmateria").path_join("assets")
    var home := OS.get_environment("HOME")
    if home != "":
        return home.path_join(".local/share/exmateria/assets")
    return ""


static func assets_root() -> String:
    var env := OS.get_environment("EXMATERIA_ASSETS_DIR")
    if env != "":
        return env
    var std_dir := standard_assets_dir()
    if std_dir != "" and DirAccess.dir_exists_absolute(std_dir.path_join("SOUND")):
        return std_dir
    # Walk up from the Godot project dir to project-assets/fft-extract/
    # for monorepo development.
    var here := ProjectSettings.globalize_path("res://").rstrip("/")
    for _i in range(8):
        var candidate := here.path_join("project-assets").path_join("fft-extract")
        if DirAccess.dir_exists_absolute(candidate):
            return candidate
        var parent := here.get_base_dir()
        if parent == "" or parent == here:
            break
        here = parent
    return ""


static func default_sound_dir() -> String:
    var root := assets_root()
    return root.path_join("SOUND") if root != "" else ""


static func default_effect_dir() -> String:
    var root := assets_root()
    return root.path_join("EFFECT") if root != "" else ""


static func default_waveset_path() -> String:
    var root := assets_root()
    return root.path_join("SOUND/WAVESET.WD") if root != "" else ""


static func default_smd_path(slot: int = 31) -> String:
    var root := assets_root()
    if root == "":
        return ""
    return root.path_join("SOUND/MUSIC_%02d.SMD" % slot)


## Optional override for parsed-effect cache (sibling project).
static func default_parsed_effect_dir() -> String:
    return OS.get_environment("FFT_PARSED_EFFECT_DIR")


## Output dir for rendered WAVs. Default: `<project>/renders/`.
static func default_render_out_dir() -> String:
    var env := OS.get_environment("FFT_SYNTH_OUT_DIR")
    if env != "":
        return env
    return ProjectSettings.globalize_path("res://renders").rstrip("/")
