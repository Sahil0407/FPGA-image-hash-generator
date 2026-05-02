#!/usr/bin/env python3
"""
send_image.py  —  PC-side script to send images to Basys 3 FPGA over UART

Requirements:
    pip install pyserial pillow

Usage:
    python send_image.py --port COM3 --image-a cat.jpg --image-b dog.jpg

    On Linux: --port /dev/ttyUSB1  (check with: ls /dev/ttyUSB*)
    On Mac:   --port /dev/cu.usbserial-*
"""

import serial
import time
import argparse
import sys
from PIL import Image

# Fix Windows console encoding
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
IMAGE_SIZE   = (128, 128)   # target size (will resize if needed)
BAUD_RATE    = 115_200

CMD_LOAD_A   = bytes([0xA0])
CMD_LOAD_B   = bytes([0xB0])
CMD_COMPARE  = bytes([0xC0])

CHUNK_SIZE   = 256          # bytes per serial write chunk (tune if needed)
INTER_CHUNK_DELAY = 0.002   # seconds between chunks (~2ms)


# -----------------------------------------------------------------------------
# Image → 12-bit pixel bytes
# -----------------------------------------------------------------------------
def image_to_12bit_bytes(path: str) -> bytes:
    """
    Load image, resize to 128x128, convert to 12-bit RGB.
    Each pixel → 2 bytes:
        Byte 0: [7:4]=0000  [3:0]=R[7:4]  G[7:4] ... wait, protocol:
        
    Protocol matches Verilog pixel_assembler:
        Byte 0 (HIGH): bits [3:0] = pixel[11:8]   (= R[7:4])
        Byte 1 (LOW) : bits [7:0] = pixel[7:0]    (= G[7:4] | B[7:4])
        
    12-bit layout: [11:8]=R_hi, [7:4]=G_hi, [3:0]=B_hi
    """
    img = Image.open(path).convert("RGB").resize(IMAGE_SIZE, Image.LANCZOS)
    pixels = list(img.getdata())

    data = bytearray()
    for (r, g, b) in pixels:
        # Take upper 4 bits of each 8-bit channel
        r4 = (r >> 4) & 0xF
        g4 = (g >> 4) & 0xF
        b4 = (b >> 4) & 0xF

        pixel_12 = (r4 << 8) | (g4 << 4) | b4   # 12-bit value

        high_byte = (pixel_12 >> 8) & 0x0F        # upper nibble → low bits of byte
        low_byte  = pixel_12 & 0xFF                # lower 8 bits

        data.append(high_byte)
        data.append(low_byte)

    assert len(data) == IMAGE_SIZE[0] * IMAGE_SIZE[1] * 2, "Unexpected data length"
    return bytes(data)


# -----------------------------------------------------------------------------
# Send with progress bar
# -----------------------------------------------------------------------------
def send_bytes(ser: serial.Serial, data: bytes, label: str):
    total  = len(data)
    sent   = 0
    start  = time.time()

    print(f"\n  Sending {label}: {total} bytes ({total//2} pixels)")

    for i in range(0, total, CHUNK_SIZE):
        chunk = data[i:i + CHUNK_SIZE]
        ser.write(chunk)
        sent += len(chunk)

        # Progress bar
        pct  = sent / total
        bar  = int(pct * 40)
        elapsed = time.time() - start
        rate = sent / elapsed if elapsed > 0 else 0
        eta  = (total - sent) / rate if rate > 0 else 0

        sys.stdout.write(
            f"\r  [{('#' * bar).ljust(40)}] "
            f"{pct*100:5.1f}%  "
            f"{sent}/{total} bytes  "
            f"{rate/1000:.1f} KB/s  "
            f"ETA {eta:.1f}s   "
        )
        sys.stdout.flush()
        time.sleep(INTER_CHUNK_DELAY)

    elapsed = time.time() - start
    print(f"\n  DONE in {elapsed:.2f}s ({total/elapsed/1000:.1f} KB/s)")


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Send images to Basys 3 FPGA for hash comparison"
    )
    parser.add_argument("--port",    required=True,  help="Serial port (e.g. COM3 or /dev/ttyUSB1)")
    parser.add_argument("--image-a", required=True,  help="Path to Image A")
    parser.add_argument("--image-b", required=True,  help="Path to Image B")
    parser.add_argument("--baud",    default=115200,  type=int, help="Baud rate (default 115200)")
    parser.add_argument("--no-compare", action="store_true",
                        help="Skip sending compare command (auto-compare happens in FPGA)")
    args = parser.parse_args()

    print("=" * 60)
    print("  Basys 3 Image Hash Sender")
    print("=" * 60)
    print(f"  Port   : {args.port}")
    print(f"  Baud   : {args.baud}")
    print(f"  Image A: {args.image_a}")
    print(f"  Image B: {args.image_b}")

    # -- Convert images ----------------------------------------------------
    print("\n  Converting images to 12-bit RGB...")
    try:
        data_a = image_to_12bit_bytes(args.image_a)
        data_b = image_to_12bit_bytes(args.image_b)
    except FileNotFoundError as e:
        print(f"\n  ERROR: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n  ERROR converting image: {e}")
        sys.exit(1)

    print(f"  Image A: {len(data_a)} bytes  OK")
    print(f"  Image B: {len(data_b)} bytes  OK")

    # -- Open serial port --------------------------------------------------
    print(f"\n  Opening serial port {args.port}...")
    try:
        ser = serial.Serial(
            port     = args.port,
            baudrate = args.baud,
            bytesize = serial.EIGHTBITS,
            parity   = serial.PARITY_NONE,
            stopbits = serial.STOPBITS_ONE,
            timeout  = 2
        )
    except serial.SerialException as e:
        print(f"\n  ERROR: Cannot open port: {e}")
        sys.exit(1)

    time.sleep(0.5)   # let FPGA settle after port open

    # -- Send Image A ------------------------------------------------------
    print("\n  [1/3] Loading Image A into FPGA BRAM...")
    ser.write(CMD_LOAD_A)
    time.sleep(0.05)
    send_bytes(ser, data_a, "Image A")

    # Wait for FPGA to finish hashing Image A
    # (16384 pixels × ~3 cycles/pixel ÷ 100MHz ≈ 0.5 ms, very fast)
    time.sleep(0.1)

    # -- Send Image B ------------------------------------------------------
    print("\n  [2/3] Loading Image B into FPGA BRAM...")
    ser.write(CMD_LOAD_B)
    time.sleep(0.05)
    send_bytes(ser, data_b, "Image B")

    time.sleep(0.1)

    # -- Send compare command ----------------------------------------------
    if not args.no_compare:
        print("\n  [3/3] Sending COMPARE command...")
        ser.write(CMD_COMPARE)
        time.sleep(0.05)

    # -- Done --------------------------------------------------------------
    ser.close()

    print("\n" + "=" * 60)
    print("  Transmission complete!")
    print("  Check Basys 3 LEDs:")
    print("    LED15 ON  = Images MATCH  (duplicate detected)")
    print("    LED14 ON  = Images DIFFER (not duplicates)")
    print("    LED13     = Loading in progress")
    print("    LED12     = Hashing in progress")
    print("=" * 60)


if __name__ == "__main__":
    main()
