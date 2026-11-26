# Vulkan presentation controls

On desktop, Kinemium selects the lowest-latency supported present mode by default:
`MAILBOX` if supported, otherwise `IMMEDIATE`, otherwise guaranteed `FIFO`.
Android continues to default to FIFO to conserve power.

Set these environment variables before launching Kinemium:

| Variable | Values | Behavior |
| --- | --- | --- |
| `KINE_VULKAN_PRESENT` | `fast`, `low-latency` | Prefer MAILBOX, then IMMEDIATE, then FIFO; desktop default |
| | `fifo`, `vsync`, `on` | Tear-free FIFO with display-refresh pacing |
| | `auto` | Prefer tear-free MAILBOX, else FIFO |
| | `immediate`, `mailbox`, `fifo-relaxed` | Use requested mode if supported, else FIFO |
| `KINE_VULKAN_ACQUIRE` | `gpu` (default), `cpu` | GPU semaphore acquire vs legacy CPU fence acquire |
| `KINE_VULKAN_IMAGES` | Integer 2..8 | Minimum requested image count, clamped by WSI capabilities; more is not necessarily faster |

```sh
# Low-latency rendering:
KINE_VULKAN_PRESENT=fast ./build/kinemium --singleplayer --map /path/to/autosave.kine

# Enable VSync / prevent tearing:
KINE_VULKAN_PRESENT=fifo ./build/kinemium --singleplayer --map /path/to/autosave.kine

# Legacy CPU-fence acquire mode for comparison or driver compatibility:
KINE_VULKAN_PRESENT=immediate KINE_VULKAN_ACQUIRE=cpu ./build/kinemium --singleplayer --map /path/to/autosave.kine
```

The compositor selects the present mode from the real Vulkan surface's supported modes at swapchain creation and resize, and logs the final mode and actual image count. IMMEDIATE can tear on some systems, use more power, and does not allow the display to physically refresh beyond its supported rate.

## GPU-side acquire synchronization

The compositor now uses a ring of binary semaphores and completion fences. A Vulkan acquire signals a semaphore, and the GPU queue's initial image transition waits for it. Each semaphore is reused only after the consuming transition's completion fence signals. This eliminates the mandatory CPU wait after each successful image acquire while retaining queue ordering for Skia, Filament, overlays, and presentation.

Swapchain resize waits for the device to idle before destroying and rebuilding the acquire ring. `KINE_VULKAN_ACQUIRE=cpu` retains the legacy CPU fence path when diagnosing a driver-specific issue.
