#!/usr/bin/env python3
"""
print_label_engine.py  --  argument-driven label printer for the
Brother PT-P950NW (PT-P900 series).

Sends raster bytes straight to the printer's built-in network print server
over LPR (TCP 515, queue 'binary_p1'). No Brother driver, no b-PAC, no
P-touch software, and no printer serial number are required -- only the
printer's IP address and a network path to it (same subnet).

Called by print-label.sh inside LinuxFixIt. Example:

    python3 print_label_engine.py \\
        --ip <printer_ip> --tape 12 --text "Example" --copies 3 --bold

All byte values come from Brother's official
"Raster Command Reference (PT-P900/P900W/P950NW/P910BT)".
"""

import argparse
import socket
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit(
        "ERROR: Python imaging library (Pillow) is not installed.\n"
        "Install it with:  sudo apt-get install -y python3-pil"
    )

# ---- Fixed printer protocol settings (do not normally change) ----
LPR_PORT = 515
LPR_QUEUE = "binary_p1"

# Tape geometry from Brother's reference. The print head is always 560 pins
# (70 bytes) wide; each tape uses a centered band of "printable" pins.
TAPES = {
    "3.5": {"width_code": 0x04, "printable": 48,  "left_margin": 248},
    "6":   {"width_code": 0x06, "printable": 64,  "left_margin": 240},
    "9":   {"width_code": 0x09, "printable": 106, "left_margin": 219},
    "12":  {"width_code": 0x0C, "printable": 150, "left_margin": 197},
    "18":  {"width_code": 0x12, "printable": 234, "left_margin": 155},
    "24":  {"width_code": 0x18, "printable": 320, "left_margin": 112},
    "36":  {"width_code": 0x24, "printable": 454, "left_margin": 45},
}

BYTES_PER_LINE = 70   # 560 pins / 8 -- fixed for this printer family
LINES_PER_MM = 14.17

# Font candidates, tried in order until one is found on the machine.
# Brother's "Helsinki" font is their name for a Helvetica/Swiss-style sans-serif.
# Helvetica is not shipped on Linux either, so we use the closest free clones:
#   Nimbus Sans / TeX Gyre Heros  = Helvetica-metric clones (best Helsinki match)
#   Liberation Sans               = Arial-metric, very close, always on Ubuntu
# The first file that exists on the machine is used.
FONTS_REGULAR = [
    "/usr/share/fonts/truetype/urw-base35/NimbusSans-Regular.otf",      # Helvetica clone (Helsinki match)
    "/usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf",      # Helvetica clone (alt path)
    "/usr/share/fonts/truetype/texgyre/texgyreheros-regular.otf",       # Helvetica clone
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",  # Arial-compatible fallback
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",                  # last resort
]
FONTS_BOLD = [
    "/usr/share/fonts/truetype/urw-base35/NimbusSans-Bold.otf",         # Helvetica clone (Helsinki match)
    "/usr/share/fonts/opentype/urw-base35/NimbusSans-Bold.otf",         # Helvetica clone (alt path)
    "/usr/share/fonts/truetype/texgyre/texgyreheros-bold.otf",          # Helvetica clone
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",     # Arial-compatible fallback
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",             # last resort
]


def load_font(bold, size):
    """Return the first available font from the candidate list."""
    for path in (FONTS_BOLD if bold else FONTS_REGULAR):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _recv_ack(sock, where):
    b = sock.recv(1)
    if b != b"\x00":
        raise RuntimeError(f"LPR negative ACK at {where}: {b!r}")


def send_lpr_job(host, port, queue, payload, job_name="label.prn", user="linuxfixit"):
    """Submit bytes directly to an LPR queue (RFC1179-style)."""
    host_tag = "linux"
    job_id = 1
    cf_name = f"cfA{job_id:03d}{host_tag}"
    df_name = f"dfA{job_id:03d}{host_tag}"

    control = (
        f"H{host_tag}\n"
        f"P{user}\n"
        f"J{job_name}\n"
        f"l{df_name}\n"
        f"U{df_name}\n"
        f"N{job_name}\n"
    ).encode("ascii")

    with socket.create_connection((host, port), timeout=10) as s:
        s.sendall(b"\x02" + queue.encode("ascii") + b"\n")
        _recv_ack(s, "receive-job")

        s.sendall(b"\x02" + str(len(control)).encode("ascii") + b" "
                  + cf_name.encode("ascii") + b"\n")
        _recv_ack(s, "control-header")
        s.sendall(control + b"\x00")
        _recv_ack(s, "control-body")

        s.sendall(b"\x03" + str(len(payload)).encode("ascii") + b" "
                  + df_name.encode("ascii") + b"\n")
        _recv_ack(s, "data-header")
        s.sendall(payload + b"\x00")
        _recv_ack(s, "data-body")


def render_text(text, tape, bold, mirror, upside_down, text_y_offset):
    """Paint the label as a black-on-white image.
    Image height = across-tape (the pins); width = label length (raster lines).

    Supports multiple lines: put a newline in the text (the form/CLI converts a
    literal "\\n" into a real line break). The font auto-shrinks to fit all
    lines on the tape, and the whole block is centered vertically."""
    printable = tape["printable"]

    n_lines = max(text.count("\n") + 1, 1)
    # One line -> 75% of tape height (unchanged). More lines -> shrink to fit.
    size = max(int(printable * 0.75 / n_lines), 8)
    font = load_font(bold, size)
    spacing = max(int(size * 0.15), 1)                      # gap between lines

    # Measure the ACTUAL ink box (default anchor). bbox[0]/bbox[1] are the gaps
    # to the left/top of the visible pixels; subtracting them centers the real
    # ink, not the font's metric box (which has extra space above/below).
    probe = ImageDraw.Draw(Image.new("L", (8, 8)))
    bbox = probe.multiline_textbbox((0, 0), text, font=font,
                                    align="center", spacing=spacing)
    tw, th = int(bbox[2] - bbox[0]), int(bbox[3] - bbox[1])

    pad = 16                                               # small left/right white space
    width = max(tw + pad * 2, 1)
    img = Image.new("L", (width, printable), 255)          # 255 = white
    draw = ImageDraw.Draw(img)

    x = (width - tw) // 2 - int(bbox[0])                    # horizontal center
    y = (printable - th) // 2 - int(bbox[1]) + text_y_offset  # true vertical center
    draw.multiline_text((x, y), text, font=font, fill=0,
                        align="center", spacing=spacing)

    if mirror:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    if upside_down:
        img = img.transpose(Image.ROTATE_180)
    return img


def image_to_raster_lines(img, tape):
    """Turn the image into one 70-byte raster line per column."""
    left = tape["left_margin"]
    px = img.load()
    w, h = img.size
    lines = []
    for x in range(w):
        buf = bytearray(BYTES_PER_LINE)
        for y in range(h):
            if px[x, y] < 128:               # dark pixel -> pin ON
                pin = left + y
                buf[pin // 8] |= (0x80 >> (pin % 8))   # MSB first
        lines.append(bytes(buf))
    return lines


def _control_header(n, tape, half_cut, cut_interval):
    """The init + control byte sequence that precedes the raster data.

    cut_interval = how many labels print between auto-cuts. Use 1 to cut after
    every label; use the copy count to print all copies connected (no cuts
    between them) and cut only once at the very end."""
    job = bytearray()

    # --- Initialization ---
    job += b"\x00" * 200                       # Invalidate: clear the buffer
    job += b"\x1b\x40"                          # ESC @  Initialize

    # --- Control codes ---
    job += b"\x1b\x69\x61\x01"                  # ESC i a 01  -> raster mode

    # ESC i z  Print information: tape width + how many raster lines
    job += b"\x1b\x69\x7a"
    job += bytes([0x84, 0x00, tape["width_code"], 0x00])
    job += n.to_bytes(4, "little")
    job += bytes([0x00, 0x00])

    iv = max(1, min(cut_interval, 0xFF))
    job += b"\x1b\x69\x4d\x40"                  # ESC i M 40 -> auto cut ON
    job += b"\x1b\x69\x41" + bytes([iv])        # ESC i A iv -> cut every `iv` labels

    # ESC i K  -> cut/feed options (one byte of on/off bits):
    #   bit 2 (0x04) = half-cut ON (cut only the label, keep the backing)
    #   bit 3 (0x08) = feed + full cut at each cut point (eject the label)
    # bit 3 is always ON so the LAST label is fed out and cut automatically --
    # the operator never has to press the cutter button. With cut_interval set
    # to the copy count, the copies still print connected (no cuts between them)
    # and the printer cuts only once at the very end.
    k = 0x08
    if half_cut:
        k |= 0x04
    job += b"\x1b\x69\x4b" + bytes([k])         # ESC i K <flags>
    job += b"\x1b\x69\x64\x0e\x00"              # ESC i d 14 -> 1mm side margins
    job += b"\x4d\x00"                          # M 00       -> no compression
    return job


def build_jobs(lines, tape, copies, half_cut, chain):
    """Return a LIST of complete LPR jobs to send, in order.

    Normal printing (chain=False): each copy is its OWN self-contained job that
    ends with Ctrl-Z (print + feed + cut), so the printer ejects and cuts every
    label automatically. Sending copies as separate jobs avoids the PT-P950NW
    stalling between FF pages and waiting for the operator to press the cutter.

    Chain printing (chain=True): all copies go in ONE job, separated by FF
    (0x0c), and the auto-cut interval is set to the copy count so the labels
    print connected back-to-back with no cuts between them. The printer still
    feeds out and cuts the LAST label automatically at the end -- nothing is
    left in the printer and the operator never presses the cutter."""
    raster = bytearray()
    for ln in lines:
        raster += b"\x47\x46\x00" + ln          # G 70 0 <70 bytes>
    n = len(lines)

    if chain:
        job = _control_header(n, tape, half_cut, copies)
        for copy in range(copies):
            job += raster
            if copy < copies - 1:
                job += b"\x0c"                  # FF  -> print this page, more follow
            else:
                job += b"\x1a"                  # Ctrl-Z -> print + feed + cut (last page)
        return [bytes(job)]

    jobs = []
    for _ in range(copies):
        job = _control_header(n, tape, half_cut, 1)
        job += raster
        job += b"\x1a"                          # Ctrl-Z -> print + feed + cut
        jobs.append(bytes(job))
    return jobs


def main():
    parser = argparse.ArgumentParser(description="Print a label on the Brother PT-P950NW.")
    parser.add_argument("--ip", required=True, help="Printer IP address")
    parser.add_argument("--tape", required=True, choices=list(TAPES),
                        help="Loaded tape width in mm")
    parser.add_argument("--text", required=True, help="Text to print")
    parser.add_argument("--copies", type=int, default=1, help="Number of labels")
    parser.add_argument("--bold", action="store_true", help="Use bold font")
    parser.add_argument("--mirror", action="store_true", help="Flip left-right")
    parser.add_argument("--upside-down", action="store_true", help="Rotate 180")
    parser.add_argument("--y-offset", type=int, default=14,
                        help="Vertical nudge: positive=down, negative=up")
    parser.add_argument("--half-cut", dest="half_cut", action="store_true",
                        default=True, help="Half-cut: cut only the label, keep backing (default on)")
    parser.add_argument("--no-half-cut", dest="half_cut", action="store_false",
                        help="Full cut through label and backing")
    parser.add_argument("--chain", action="store_true",
                        help="Chain print: labels connected with no cuts between copies; one cut at the end and the last label is still ejected")
    args = parser.parse_args()

    if args.copies < 1:
        sys.exit("ERROR: --copies must be 1 or more.")
    if not args.text.strip():
        sys.exit("ERROR: --text is empty.")

    # Allow users to type a literal "\n" to get a second line.
    args.text = args.text.replace("\\n", "\n")

    tape = TAPES[args.tape]

    img = render_text(args.text, tape, args.bold, args.mirror,
                      args.upside_down, args.y_offset)
    lines = image_to_raster_lines(img, tape)
    jobs = build_jobs(lines, tape, args.copies, args.half_cut, args.chain)

    total_bytes = sum(len(j) for j in jobs)
    print(f"Label : '{args.text}' on {args.tape}mm tape"
          f"{' (bold)' if args.bold else ''}")
    print(f"Copies: {args.copies}")
    print(f"Cut   : {'half-cut' if args.half_cut else 'full cut'}, "
          f"{'chain (connected, one cut at end, last ejected)' if args.chain else 'cut + eject each'}")
    print(f"Size  : {img.size[0]} raster lines  ({img.size[0] / LINES_PER_MM:.1f} mm long each)")
    print(f"Job   : {len(jobs)} job(s), {total_bytes} bytes total")

    print(f"\nSending via LPR to {args.ip}:{LPR_PORT} queue '{LPR_QUEUE}' ...")
    try:
        for i, job in enumerate(jobs, 1):
            if len(jobs) > 1:
                print(f"  -> sending label {i}/{len(jobs)} ...")
            send_lpr_job(args.ip, LPR_PORT, LPR_QUEUE, job)
    except RuntimeError as e:
        sys.exit(f"LPR protocol failed: {e}")
    except OSError as e:
        sys.exit(
            f"Could not reach the printer: {e}\n"
            f"  -> is the printer powered on and on the same subnet as this PC?\n"
            f"  -> try:  ping {args.ip}"
        )
    print(f"Sent. {args.copies} label(s) should be coming out now.")


if __name__ == "__main__":
    main()
