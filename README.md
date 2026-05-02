# FPGA-Based Duplicate Image Detection System

> Detect duplicate images using pure hardware logic — no CPU, no OS, no ML.  
> Built on the **Basys 3 FPGA (Artix-7)** using **Verilog RTL**, with a Python script on the PC side for image streaming over **UART**.

---

## 📌 Overview

This project implements a complete hardware pipeline on an FPGA that:

1. **Receives** a 128×128 RGB image from a PC over UART (115200 baud)
2. **Stores** it in Xilinx Block RAM (RAMB36E1 primitives)
3. **Computes** a 32-bit hash over all 16,384 pixels using a rotate-XOR algorithm
4. **Compares** two image hashes in a single clock cycle
5. **Signals** the result on the onboard LEDs — no display required

Everything runs at **100 MHz** on the Artix-7 FPGA fabric. No microcontroller, no embedded processor — pure synthesizable RTL logic.

---

## 🗂️ Project Structure

```
fpga-image-hash-detector/
│
├── uart_rx.v              # UART receiver — 115200 baud, 8-N-1, with 2-FF metastability sync
├── uart_tx.v              # UART transmitter — optional, for debug output
├── pixel_assembler.v      # FSM: parses command bytes, reconstructs 12-bit pixels, drives BRAM write
├── image_bram.v           # True dual-port Block RAM — 32768 × 12-bit (stores 2 images)
├── hash_engine.v          # Sequential rotate-XOR hash engine over 16,384 pixels
├── top_controller.v       # Top-level FSM — wires all modules, drives LEDs
├── tb_top.v               # Vivado behavioral simulation testbench
├── basys3_constraints.xdc # Pin assignments — clock, reset, UART RX, LEDs
└── send_image.py          # PC-side Python script — converts image and streams over UART
```

---

## 🏗️ System Architecture

```
PC (Python Script)
        │
        │  UART @ 115200 baud
        │  2 bytes per pixel (12-bit RGB)
        ▼
┌─────────────────────────────────────────────────────────────┐
│                    Basys 3 FPGA (Artix-7)                   │
│                                                             │
│   ┌──────────┐    ┌──────────────────┐    ┌─────────────┐  │
│   │  UART RX │───▶│ Pixel Assembler  │───▶│  Image BRAM │  │
│   └──────────┘    │  (FSM)           │    │  32K × 12b  │  │
│                   └──────────────────┘    └──────┬──────┘  │
│                                                  │         │
│                                          ┌───────▼──────┐  │
│                                          │ Hash Engine  │  │
│                                          │ (rotate-XOR) │  │
│                                          └───────┬──────┘  │
│                                                  │         │
│                                          ┌───────▼──────┐  │
│                                          │Top Controller│  │
│                                          │   (compare)  │  │
│                                          └───────┬──────┘  │
│                                                  │         │
│                                             LEDs [15:0]    │
└─────────────────────────────────────────────────────────────┘
```

---

## 📡 UART Protocol

### Commands (1 byte, sent before pixel data)

| Byte   | Meaning                          |
|--------|----------------------------------|
| `0xA0` | Load Image A (next 32768 bytes)  |
| `0xB0` | Load Image B (next 32768 bytes)  |
| `0xC0` | Trigger hash comparison          |

### Pixel Format

Each 12-bit pixel is sent as **2 bytes**:

```
Byte 0 (HIGH): [7:4] = 0000  |  [3:0] = R[7:4]
Byte 1 (LOW) : [7:0] = G[7:4] | B[7:4]

12-bit layout: [11:8] = R_hi, [7:4] = G_hi, [3:0] = B_hi
```

**Total bytes per image:** `128 × 128 × 2 = 32,768 bytes`

---

## 🧠 Hash Algorithm

```
seed = 0xDEADBEEF
for each 12-bit pixel p in image:
    hash = rotl(hash, 1) + (hash XOR zero_extend(p))
```

- Pixel **order matters** — reordered images hash differently
- Completes in **~16,400 clock cycles** → under **200 µs** at 100 MHz
- Much stronger avalanche effect than plain XOR

---

## 💾 BRAM Layout

| Address Range       | Contents       |
|---------------------|----------------|
| `0x0000` – `0x3FFF` | Image A pixels |
| `0x4000` – `0x7FFF` | Image B pixels |

Inferred as Xilinx **RAMB36E1** block RAM primitives using `(* ram_style = "block" *)` attribute.

---

## 💡 LED Indicators

| LED    | Meaning                              |
|--------|--------------------------------------|
| LED15  | 🟢 **MATCH** — images are duplicates |
| LED14  | 🔴 **MISMATCH** — images differ      |
| LED13  | Image loading in progress            |
| LED12  | Hashing in progress                  |
| LED11  | Image B hash ready                   |
| LED10  | Image A hash ready                   |
| LED9   | Currently loading: 0 = A, 1 = B      |
| LED7:0 | Lower byte of last hash (debug)      |

---

## ⚙️ Setup and Usage

### Requirements

**Hardware:**
- Basys 3 FPGA board (Artix-7 XC7A35T-1CPG236C)
- Micro-USB cable (same one used for programming — carries both JTAG and UART)

**Software:**
- Xilinx Vivado (2020.x or later)
- Python 3.x
- Python packages: `pip install pyserial pillow`

---

### Step 1 — Vivado Project Setup

1. Open Vivado → **Create Project** → RTL Project
2. Target part: `xc7a35tcpg236-1` (Basys 3)
3. Add all `.v` files as **Design Sources**
4. Add `basys3_constraints.xdc` as **Constraints**
5. Set `top_controller` as the **Top Module**
6. Run: **Synthesis → Implementation → Generate Bitstream**
7. **Program Device** via Hardware Manager

---

### Step 2 — Find Your COM Port

The Basys 3 micro-USB creates **two COM ports** in Windows:

```
Device Manager → Ports (COM & LPT)
  ├── USB Serial Port (COM6)  ← JTAG / Vivado
  └── USB Serial Port (COM7)  ← UART / Python script  ✅ use this one
```

On Linux: `ls /dev/ttyUSB*` — use the higher-numbered device.

> ⚠️ **Close Vivado Hardware Manager before running the Python script.** Both share the same USB chip and will conflict.

---

### Step 3 — Send Images from PC

```bash
python send_image.py --port COM7 --image-a photo1.jpg --image-b photo2.jpg
```

Any image format works (JPG, PNG, BMP, etc.) — the script auto-resizes to 128×128.

**Expected output:**
```
Opening COM7 at 115200 baud...
Port open OK

[1/3] Converting Image A...
      32768 bytes ready
[2/3] Sending command byte for Image A...
[3/3] Sending Image A pixels...
       3.9%  (1280/32768 bytes)
      ...
      DONE: Image A sent!

ALL DONE — check Basys 3 LEDs:
  LED15 ON = MATCH (duplicate)
  LED14 ON = MISMATCH (different)
```

> ⏱️ At 115200 baud, each image takes ~5–6 minutes to transfer (~12 min total for both).

---

### Step 4 — Read the Result

| LED State  | Meaning                        |
|------------|-------------------------------|
| LED15 ON   | ✅ Images are duplicates       |
| LED14 ON   | ❌ Images are different        |

---

## 🧪 Simulation (Vivado)

1. Add `tb_top.v` as a **Simulation Source**
2. Right-click → **Set as Top**
3. Click **Run Behavioral Simulation**
4. Check the **Tcl Console** for pass/fail output

The testbench sends 16 pixels (not 16,384) for simulation speed. To match, the testbench overrides `TOTAL_PIXELS=16` via a module parameter — real hardware still uses 16,384.

**Expected Tcl Console output:**
```
=== Sending Image A command ===
Sent 16 Image A pixels
=== Sending Image B command ===
Sent 16 Image B pixels (identical to A)
LED15 (MATCH) = 1
PASS: Images match as expected
```

---

## ⏱️ Timing Summary

| Operation              | Time @ 100 MHz   |
|------------------------|------------------|
| Receive 1 pixel (2 B)  | ~174 µs          |
| Receive full image     | ~5.7 minutes     |
| Hash full 128×128      | < 200 µs         |
| Hash comparison        | 1 clock cycle    |

---

## 🚀 Possible Extensions

| Feature | Description |
|---|---|
| **Higher baud rate** | FT2232HQ supports up to 12 Mbaud — reduce transfer time from 6 min to ~30 sec |
| **SHA-256 core** | Replace hash engine with OpenCores SHA-256 for cryptographic-strength hashing |
| **Perceptual hash** | DCT-based pHash for similarity detection (not just exact match) |
| **Multiple images** | Extend BRAM depth and add image index register to store a database |
| **UART TX result** | Use `uart_tx.v` to send hash value back to PC for logging |

---

## 🛠️ Tools Used

| Tool | Purpose |
|---|---|
| Xilinx Vivado | Synthesis, implementation, simulation |
| Verilog HDL | RTL design of all hardware modules |
| Python + Pillow | Image conversion and UART streaming |
| PySerial | Serial communication from PC |
| Basys 3 (Artix-7) | Target FPGA hardware |

---

## 👤 Author

**Sahil Amrut Pisal**  
B.Tech Electronics and Telecommunication (Honors in VLSI)  
Dwarkadas J. Sanghvi College of Engineering, Mumbai  
[LinkedIn](https://www.linkedin.com/in/sahil-pisal-33113a337/) | sahilpisal0407@gmail.com
