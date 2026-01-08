$activeBorderColor = rgb({{ selection_background_strip }}) rgb({{ accent_strip }}) 45deg
$activeBarBoderColor = rgb({{ color0_strip }})


general {
    col.active_border = $activeBorderColor
}

group {
    col.border_active = $activeBorderColor

    groupbar {
        col.active = $activeBarBoderColor
      }
}
