# MagnetarOS ASCII logos

| file | what |
|---|---|
| `magnetaros-detailed.txt` | full dipole-field logo + wordmark (57 cols) |
| `magnetaros-medium.txt` | mid-size logo + wordmark |
| `magnetaros-simple.txt` | 5-line logo + wordmark |
| `magnetaros-tiny.txt` | 5-line, 9-col mark only (fetch panels, prompts) |
| `wordmark.txt` | wordmark alone |
| `*-color.sh` | same art with a 24-bit ANSI radial gradient (white core → cyan → blue → violet → magenta) |
| `magnetaros-preview.png` | rendered preview of the colour versions |

## Use

    sh magnetaros-detailed-color.sh          # print it
    sh magnetaros-simple-color.sh > /etc/motd  # login banner (needs truecolor terminal)

fastfetch: `fastfetch --file-raw magnetaros-medium-color.sh` won't work directly (it's a script) — run it once with
`sh magnetaros-medium-color.sh > logo.ans` and point fastfetch at it with `--logo-type file-raw --logo logo.ans`.
neofetch: `--ascii "$(sh magnetaros-simple-color.sh)"` or use the plain `.txt` with `--ascii_colors 5 4 6`.

Colours are 256-stop truecolor. If your terminal is 16-colour only, use the `.txt` files and let the tool colour them.
