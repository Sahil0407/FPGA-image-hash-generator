# FPGA-Based Duplicate Image Detection System

> Detect duplicate images using pure hardware logic — no CPU, no OS, no ML.  
> Built on the **Basys 3 FPGA (Artix-7)** using **Verilog RTL**, with a Python script on the PC side for image streaming over **UART**.

---


## 📌 Overview

This project implements a hardware accelerator on a Basys 3 FPGA (Artix-7) that detects duplicate images. Two 128×128 RGB images are sent over UART, stored in on-chip BRAM, hashed with a custom 32-bit algorithm, and compared – all in hardware.

Key features:

1. Real‑time UART reception at 115200 baud
2. **12‑bit RGB** pixel streaming (2 bytes per pixel)
3. Dual‑port BRAM for simultaneous write and read (though used sequentially in this design)
4. Custom fast hash: hash = rotl1(hash) + (hash XOR pixel)
5. Immediate match/mismatch indication via onboard LEDs
6. Python script for image conversion and transmission

Everything runs at **100 MHz** on the Artix-7 FPGA fabric. No microcontroller, no embedded processor; pure synthesizable RTL logic.

---

## 🧠 How It Works

1. **PC** sends command `0xA0` followed by 32768 bytes (128×128×2) representing Image A.
2. **Pixel assembler** reconstructs 12‑bit pixels and writes them to BRAM (addresses 0 – 16383).
3. **Hash engine** reads the entire Image A from BRAM, computes a 32‑bit hash, and stores it in an internal register.
4. **PC** sends command `0xB0` followed by Image B data, stored at addresses 16384 – 32767.
5. **Hash engine** computes hash of Image B and stores it.
6. **PC** optionally sends `0xC0` to trigger comparison (the design auto‑compares when both hashes are ready).
7. **Result** is shown on LEDs:
   - `LED15` = 1 → images match (duplicate)
   - `LED14` = 1 → images differ

During image loading `LED13` is on; during hashing `LED12` is on. Lower 8 bits of the last computed hash appear on `LED[7:0]` for debugging.

---

## 🛠️ Hardware Requirements

- **FPGA board:** Digilent Basys 3 (XC7A35T-1CPG236C)
- **On‑chip memory:** 2250 Kb BRAM (sufficient for two 128×128 12‑bit images)
- **UART:** USB‑UART bridge (on‑board, connects to PC via micro‑USB)
- **Clock:** 100 MHz on‑board oscillator
- **Reset:** Center button (BTNC)
- **LEDs:** 16 general‑purpose LEDs


---
## 🗂️ Project Structure

```
FPGA-image-hash-generator/
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



## 🚀 Getting Started

### 1. Prerequisites

- **Vivado** 2025.1 (or later) – for synthesis, implementation, and bitstream generation.
- **Python 3.8+** with packages:
---
```
pip install pyserial pillow
```
- **Basys 3** board with USB cable (programming + UART).

### 2. Simulation (optional)

Open the project in Vivado, add all Verilog files and the testbench (`tb_top.v`). Run behavioral simulation. The testbench sends 16 red pixels (instead of full 16384) and verifies the match condition. Expected output:
```
Image A hash computed: 1f3f8384
Image B hash computed: 1f3f8384
LED15 (MATCH) = 1
LED14 (MISMATCH) = 0
PASS: Images match as expected
```

### 3. Synthesis & Implementation

- Set `top_controller` as the top module.
- Add the constraint file (`basys3.xdc`).
- Run **Synthesis**, **Implementation**, then **Generate Bitstream**.
- Program the FPGA (Open Hardware Manager → Auto Connect → Program Device).

### 4. Using the Python Script

After programming the FPGA, **press and release the centre reset button (BTNC)** to ensure a clean initial state.

Then run the Python script from your terminal:

```bash
# Windows (example with COM5)
python send_image.py --port COM5 --image-a cat.jpg --image-b cat.jpg

# Linux (example with /dev/ttyUSB0)
python send_image.py --port /dev/ttyUSB0 --image-a cat.jpg --image-b cat.jpg
```
Arguments:

--port : serial port (e.g., COM3, /dev/ttyUSB0)
--image-a : path to first image
--image-b : path to second image
--baud : baud rate (default 115200, should match FPGA)
--no-compare : skip sending compare command (auto‑compare still works)

The script will:
Resize both images to 128×128
Convert each pixel to 12‑bit RGB (4 bits per channel)
Send the command and pixel data in chunks
Print a progress bar and transmission statistics

After transmission, read the match/mismatch result from the LEDs on the Basys 3.

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

### Requirements

**Hardware:**
- Basys 3 FPGA board (Artix-7 XC7A35T-1CPG236C)
- Micro-USB cable (same one used for programming — carries both JTAG and UART)

**Software:**
- Xilinx Vivado (2020.x or later)
- Python 3.x
- Python packages: `pip install pyserial pillow`

**Simulation**
The testbench (tb_top.v) uses a reduced TOTAL_PIXELS = 16 to keep simulation time short. It sends 16 red pixels for Image A and the same for Image B, then checks that LED15 goes high.
Hardware Test Cases
Test	Image A	         Image B	  Expected LED
1	cat.jpg	     cat.jpg (same file)    LED15 ON
2	cat.jpg	          dog.jpg	    LED14 ON
3	solid red	 solid red	    LED15 ON
4	solid red	solid green	    LED14 ON

---

## ⏱️ Performance

| Metric                                | Value                                     |
|---------------------------------------|-------------------------------------------|
| UART baud rate                        | 115200 bps                                |
| Time to load one image (32768 bytes)  | ≈ 2.85 seconds                            |
| Hash computation time (16384 pixels)  | ≈ 0.5 ms (100 MHz, 3 cycles/pixel)        |
| Total comparison time (both images)   | ≈ 5.7 seconds + 1 ms                      |
| BRAM utilisation                      | ~49 KB (well within the 281 KB available) |
| Power consumption (typical)           | 150 mW (core)                             |
---





## 👤 Author

**Sahil Amrut Pisal**  
B.Tech Electronics and Telecommunication (Honors in VLSI)  
Dwarkadas J. Sanghvi College of Engineering, Mumbai  
[LinkedIn](https://www.linkedin.com/in/sahil-pisal-33113a337/) | sahilpisal0407@gmail.com
