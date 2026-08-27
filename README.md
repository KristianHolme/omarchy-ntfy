# omarchy-ntfy

An [Omarchy](https://omarchy.org/) bar plugin for [ntfy.sh](https://ntfy.sh/). Subscribe to topics, send messages, and get incoming messages as desktop notifications without keeping the web app open.

Plugin id: `kristianholme.ntfy`

## Install

```bash
omarchy plugin add https://github.com/KristianHolme/omarchy-ntfy.git --enable
```

The widget defaults to the right side of the bar. Move it with:

```bash
omarchy bar move kristianholme.ntfy
```

## Update

```bash
omarchy plugin update kristianholme.ntfy
```

## Remove

```bash
omarchy plugin remove kristianholme.ntfy
```

## Usage

- Left-click the bar icon to open the panel.
- Right-click the bar icon, or click the ntfy mark in the panel header, to mute system notifications. The live feed still updates. Muted uses the theme muted color.
- The header switch turns the service off completely: no stream, no send, no notifications. Off uses the theme urgent/red color.
- Mute next to the topic picker silences one topic, or every topic when **All** is selected.

Topic names are the secret. This plugin talks to the public `https://ntfy.sh` server and does not store credentials.

## License

MIT
