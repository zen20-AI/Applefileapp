# dmgbuild settings for Petal's disk image (see scripts/build-dmg.sh).
import os.path

app = defines["app"]
format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [app, defines["readme"]]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents/Resources/AppIcon.icns")
background = defines["background"]
window_rect = ((200, 160), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 190),
    "Applications": (490, 190),
    os.path.basename(defines["readme"]): (600, 330),
}
hide_extensions = [os.path.basename(app)]
