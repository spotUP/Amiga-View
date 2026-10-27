# Vendored wasabi

Source: https://github.com/creep-ltx/wasabi (MIT, see LICENSE), commit be4c055 (release v0.11b2),
copied from Up_Rough_Demo_System `tools/wasabi` (commit ffefb8325), where the same files are vendored.

- `wasabi.py` = the single-file Python 3 client (stdlib only), unmodified. scripts/bundle.sh copies
  it into the app's Resources; "Reset Amiga" runs it as `wasabi.py --host <amigaHost> reboot --yes`.
- `Tests/AmigaViewTests/Fixtures/mock_wasabid.py` = Up_Rough's copy of the upstream mock daemon
  (it carries Up_Rough's LOCAL verbs.log change). The reset test checks its "REBOOT requested" line.

To update: copy both files again and change the commits above.
