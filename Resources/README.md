# Resources

`AppIcon.icns` is generated, not hand-authored. Regenerate it with:

```bash
swift Scripts/make-icon.swift
```

The mark is Hugo: tricolour head, white blaze, long ears, and the red thread he
wears. Keeping it as code rather than a folder of exported PNGs means a change
to the icon shows up as a readable diff, and every size in the iconset stays
consistent by construction.

The `.icns` is committed so that building the app needs no extra step;
`Scripts/build-app.sh` regenerates it automatically if it is missing.
