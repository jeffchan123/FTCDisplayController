This project creates a centralized display controller to remotely manage (mirror and interact) with FTC tournament display using Firesticks.

# Features
- Monitor and manage seven Fire TV Sticks from one local browser dashboard.
- Support E9L29Y, K2R2TE, and M3N6RA models with model-specific toolbar-hiding sequences.
- Configure the scoring server, event code, and display type: Audience, Field, Pit, Sponsor, or Championship Bar.
- Choose monitor-only startup or automatically set up assigned displays.
- View screen previews with Realtime, 2-second, 5-second, or 10-second refresh options.
- Show connection status, preview age, stale-preview warnings, and activity logs.
- Automatically reconnect offline devices, with optional restoration of their assigned display.
- Assign location names to devices and include them in scrcpy window titles.
- Select devices for group setup, reconnect, recovery, and scrcpy actions.
- Minimize unused device cards and automatically reflow the dashboard.
- Recover displays by reopening their saved URL and rerunning the toolbar-hiding sequence.
- Send remote commands: Wake, Home, Back, Menu, directional arrows, and OK.
- Open scrcpy for live viewing and control at 800-pixel maximum size, 15 FPS, and 1 Mbps.
- Apply and verify screensaver and sleep settings during display setup.
- Save device names, assignments, selections, minimized states, and connection preferences across restarts.
- Run locally on macOS using Python 3, ADB, and scrcpy, with no additional Python packages required.

# Supported Firesticks
| Model number | Device | OS / Android base | CPU | RAM | FTC controller suitability |
|---|---|---|---|---|---|
| E9L29Y | Stick 4K, 2018 | Fire OS 6 / Android 7.1 | Quad-core 1.7 GHz | 1.5 GB | Confirmed working |
| K2R2TE | Stick 4K Max, 2021 | Fire OS 7 / Android 9 | Quad-core 1.8 GHz | 2 GB | Confirmed working |
| M3N6RA | Stick 4K, 2023 | Fire OS 8 / Android 11 | Quad-core Cortex-A55, 1.7 GHz | 2 GB | Confirmed working |
| K3R6AT | Stick 4K Max, 2023 | Fire OS 8 / Android 11 | Quad-core Cortex-A55, 2.0 GHz | 2 GB | Strong candidate; controller testing required |
| S3L46N | Stick 3rd gen, 2020 | Fire OS 7 / Android 9 | Quad-core 1.7 GHz | 1 GB | Candidate for basic 1080p displays |
| S3L46N | Stick Lite, 2020 | Fire OS 7 / Android 9 | Quad-core 1.7 GHz | 1 GB | Candidate; less memory headroom |
| S3L46N | Stick HD, 2024 | Fire OS 7 / Android 9 | Quad-core 1.7 GHz | 1 GB | Candidate for basic 1080p displays |
| LY73PR | Stick 2nd gen / Basic Edition | Fire OS 5 / Android 5.1 | Quad-core 1.3 GHz | 1 GB | Backup only; older hardware and software |
| W87CUN | Stick 1st gen, 2014 | Fire OS 5 / Android 5.1 | Dual-core Cortex-A9, 1.0 GHz | 1 GB* | Avoid for event deployment |
| LDC9WZ | Fire TV pendant, 2017 | Fire OS 6 / Android 7.1 | Quad-core Cortex-A53, 1.5 GHz | 2 GB | Potentially usable; testing required |

*W87CUN divides its RAM into 512 MB system memory and 512 MB video memory.*

**S3L46N is shared by multiple products:** confirm the product name in Settings.

**Compatibility:** “Confirmed working” refers to devices tested with this controller. Other models require testing and controller configuration. Vega OS devices are not compatible with the current Android ADB/scrcpy approach.

# Mac requiremnts
- Any mac that runs python3, ADB, and strcpy.  My current setup is 2010 Macbook Pro High Sierra (10.13.6) running an older version of scrcpy (2.7).

# How to run
- On a mac terminal, run .command file, a web page will open to show the application.
- TIP: You can create an alias to the .command file and put on the desktop for easy access.

# Screenshot
<img width="1392" height="818" alt="Screen Shot 2026-10-14 at 10 46 49 AM" src="https://github.com/user-attachments/assets/c73cc3e4-5dc8-4c76-bea9-256512f3dc1c" />

# Walkthrough Video
- https://youtu.be/2tGv_L5cdYM

# Tips
- If using for the field display and game sounds, use an ethernet adapter and wifi together.  Using Wifi only results in 1/2 second latency for the game sounds.

# Known issues
- Firesticks are a consumer product, Amazon sends all sorts of random popups and notificaitons, test each firestick again prior to an event to clear out stray notifications.
