#!/usr/bin/env bash
# flash_m8p_v2_sb2209.sh
# Automated build and flashing of firmware for BTT Manta M8P V2.0 (STM32H723) and EBB SB2209 (RP2040 CAN toolhead)

set -euo pipefail

# --- User configuration ---
CB1_USER="${USER}"
KATAPULT_DIR="$HOME/katapult"
KLIPPER_DIR="$HOME/klipper"
CAN_INTERFACE="can0"
CAN_BITRATE=1000000
DFU_DEVICE_ID="0483:df11"     # DFU VID:PID for STM32 DFU
RP2040_USB_ID="2e8a:0003"     # USB VID:PID for RP2040 bootloader

# --- Ensure dependencies ---
echo "Installing dependencies..."
sudo apt update
sudo apt install -y dfu-util can-utils python3-can

# --- Build Katapult for M8P v2.0 ---
echo
echo "### 1) Build Katapult for M8P V2.0 ###"
echo "In menuconfig: set MCU to STM32H723, Bootloader offset=0x20000, enable CAN at ${CAN_BITRATE}bps"
pushd "$KATAPULT_DIR"
make menuconfig
make clean
make
popd

# --- Build Klipper for M8P v2.0 ---
echo
echo "### 2) Build Klipper firmware for M8P V2.0 ###"
echo "In menuconfig: select STM32H723, Bootloader offset=0x20000, USB+CAN bridge, CAN at ${CAN_BITRATE}bps"
pushd "$KLIPPER_DIR"
make menuconfig
make clean
make
popd

# --- Flash Katapult bootloader to M8P ---
echo
echo "### 3) Flash Katapult bootloader to M8P ###"
echo "Enter DFU mode: hold BOOT0, press RESET, then release BOOT0"
read -rsp $'Press any key when in DFU...\n'
sudo dfu-util -a 0 \
    --dfuse-address 0x08000000:force:leave \
    -d $DFU_DEVICE_ID \
    -D "$KATAPULT_DIR/out/katapult.bin"

# --- Flash Klipper to M8P ---
echo
echo "### 4) Flash Klipper firmware to M8P ###"
echo "Re-enter DFU: hold BOOT0, press RESET, release BOOT0"
read -rsp $'Press any key when in DFU...\n'
sudo dfu-util -a 0 \
    --dfuse-address 0x08020000 \
    -d $DFU_DEVICE_ID \
    -D "$KLIPPER_DIR/out/klipper.bin"

# --- Setup CAN interface ---
echo
echo "### 5) Bring up CAN interface ###"
sudo ip link set "$CAN_INTERFACE" down || true
sudo ip link set "$CAN_INTERFACE" type can bitrate "$CAN_BITRATE"
sudo ip link set "$CAN_INTERFACE" up
echo "CAN interface $CAN_INTERFACE is up at ${CAN_BITRATE}bps"

# --- Query CAN bootloaders on CB1 ---
echo
echo "### 6) Query CAN bootloader nodes ###"
python3 "$KATAPULT_DIR/scripts/flash_can.py" -i "$CAN_INTERFACE" -q

# --- Build Katapult for SB2209 (RP2040) ---
echo
echo "### 7) Build Katapult for SB2209 ###"
echo "In menuconfig: select RP2040, set CAN pins per documentation, CAN=${CAN_BITRATE}bps"
pushd "$KATAPULT_DIR"
make menuconfig
make clean
make
popd

# --- Flash Katapult to SB2209 via USB ---
echo
echo "### 8) Flash SB2209 bootloader (USB) ###"
echo "Enter RP2040 bootloader: hold BOOTSEL, press RESET"
read -rsp $'Press any key when in RP2040 bootloader...\n'
sudo make -C "$KATAPULT_DIR" flash FLASH_DEVICE=$RP2040_USB_ID

# --- Flash Klipper to SB2209 via CAN ---
echo
echo "### 9) Flash Klipper to SB2209 over CAN ###"
echo "Disconnect USB, connect CAN cable, power on SB2209"
read -rsp $'Press any key when CAN cable is connected...\n'
echo "Query CAN nodes for SB2209 Katapult:"
python3 "$KATAPULT_DIR/scripts/flashtool.py" -i "$CAN_INTERFACE" -q
read -p "Enter SB2209 UUID: " SB_UUID
python3 "$KATAPULT_DIR/scripts/flashtool.py" -i "$CAN_INTERFACE" -u "$SB_UUID" -f "$KLIPPER_DIR/out/klipper.bin"

echo
echo "=== Flashing complete! ==="
echo "Restart Klipper service: sudo service klipper restart"
echo "Use printer.cfg to map both MCUs by their UUIDs."
