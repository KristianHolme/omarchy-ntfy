# omarchy-ntfy

An [Omarchy](https://omarchy.org/) bar plugin for [ntfy.sh](https://ntfy.sh/). Subscribe to topics, send messages, and get incoming messages as desktop notifications without keeping the web app open.

Plugin id: `kristianholme.ntfy`
## Screenshots
<img width="2045" height="2160" alt="image" src="https://github.com/user-attachments/assets/6bc61fb6-95c4-4d6c-9247-c0d9786528b8" />
  <table>
    <tr>
      <td align="center" width="50%">
        <img width="999" height="563" alt="ntfy-send" src="https://github.com/user-attachments/assets/6054d06a-9dcf-4e88-be29-f4be04f9ba19" />
      </td>
      <td align="center" width="50%">
       <img width="1010" height="436" alt="ntfy-settings" src="https://github.com/user-attachments/assets/a533b197-0ac0-4819-ba47-298862d1562a" />
      </td>
    </tr>
  </table>

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
- The feed shows titles with emoji tags, image attachments, priority, click links, and action buttons (`view`, `http`, `copy`). Android-only `broadcast` actions stay disabled.
- Right-click the bar icon, or click the message icon in the panel header, to mute system notifications. The live feed still updates. Muted uses the theme muted color.
- The header switch turns the service off completely: no stream, no send, no notifications. Off uses the theme urgent/red color.
- Mute next to the topic picker silences one topic, or every topic when **All** is selected.

Topic names are the secret. This plugin talks to the public `https://ntfy.sh` server and does not store credentials.

## License

MIT
