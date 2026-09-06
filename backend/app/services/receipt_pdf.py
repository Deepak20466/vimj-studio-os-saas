import io
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import List, Optional

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

LOGO_PATH = Path(__file__).resolve().parent.parent / "assets" / "logo.jpeg"

BRAND_ORANGE = colors.HexColor("#FFA500")
BRAND_YELLOW = colors.HexColor("#FFF500")
BRAND_ALICE_BLUE = colors.HexColor("#F0F8FF")
TEXT_DARK = colors.HexColor("#1F2933")
TEXT_MUTED = colors.HexColor("#5A6472")
BORDER_GREY = colors.HexColor("#D9DEE4")
GREEN = colors.HexColor("#1E8E3E")
RED = colors.HexColor("#D93025")

MONTH_NAMES = [
    "", "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]


def build_fee_receipt_pdf(
    *,
    receipt_no: str,
    student_name: str,
    activity_names: List[str],
    month: int,
    year: int,
    amount_paid: Decimal,
    balance_amount: Decimal,
    payment_mode: str,
    paid_date: date,
    approved_by: Optional[str] = None,
    academy_name: str = "VIMJ Studio",
    academy_contact: str = "hello@vimjstudio.com  |  +91 98000 00000",
    student_contact: Optional[str] = None,
) -> bytes:
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    width, height = A4
    margin = 18 * mm

    # ---- Header band ----
    header_h = 34 * mm
    c.setFillColor(BRAND_ORANGE)
    c.rect(0, height - header_h, width, header_h, fill=True, stroke=False)

    text_x = margin
    if LOGO_PATH.exists():
        logo_size = 20 * mm
        c.drawImage(
            str(LOGO_PATH),
            margin,
            height - 15 * mm - logo_size / 2,
            width=logo_size,
            height=logo_size,
            preserveAspectRatio=True,
            mask="auto",
        )
        text_x = margin + logo_size + 4 * mm

    c.setFillColor(colors.white)
    c.setFont("Helvetica-Bold", 18)
    c.drawString(text_x, height - 15 * mm, academy_name)
    c.setFont("Helvetica", 9)
    c.drawString(text_x, height - 21 * mm, academy_contact)
    c.setFont("Helvetica-Oblique", 9)
    c.drawString(text_x, height - 27 * mm, "Fee Payment Receipt")

    c.setFont("Helvetica-Bold", 20)
    c.drawRightString(width - margin, height - 14 * mm, "RECEIPT")
    c.setFont("Helvetica-Bold", 10)
    c.drawRightString(width - margin, height - 21 * mm, f"Receipt No: {receipt_no}")
    c.setFont("Helvetica", 9)
    c.drawRightString(width - margin, height - 26.5 * mm, f"Date: {paid_date.strftime('%d %b %Y')}")
    c.drawRightString(width - margin, height - 31 * mm, f"Period: {MONTH_NAMES[month]} {year}")

    y = height - header_h - 12 * mm

    # ---- Bill To / From ----
    col_w = (width - 2 * margin - 10 * mm) / 2
    c.setFillColor(TEXT_DARK)
    c.setFont("Helvetica-Bold", 10)
    c.drawString(margin, y, "Billed To")
    c.drawString(margin + col_w + 10 * mm, y, "From")
    y -= 5.5 * mm

    c.setStrokeColor(BRAND_ORANGE)
    c.setLineWidth(1.2)
    c.line(margin, y + 2 * mm, margin + 28 * mm, y + 2 * mm)
    c.line(margin + col_w + 10 * mm, y + 2 * mm, margin + col_w + 10 * mm + 14 * mm, y + 2 * mm)

    c.setFont("Helvetica", 10)
    c.setFillColor(TEXT_DARK)
    c.drawString(margin, y - 4 * mm, student_name)
    c.drawString(margin + col_w + 10 * mm, y - 4 * mm, academy_name)
    c.setFont("Helvetica", 9)
    c.setFillColor(TEXT_MUTED)
    c.drawString(margin, y - 9.5 * mm, student_contact or "Student")
    c.drawString(margin + col_w + 10 * mm, y - 9.5 * mm, academy_contact)

    y -= 22 * mm

    # ---- Enrolled activities strip ----
    activity_line = ", ".join(activity_names) if activity_names else "N/A"
    c.setFillColor(BRAND_ALICE_BLUE)
    c.rect(margin, y - 9 * mm, width - 2 * margin, 9 * mm, fill=True, stroke=False)
    c.setFillColor(TEXT_DARK)
    c.setFont("Helvetica-Bold", 10)
    c.drawString(margin + 3 * mm, y - 6 * mm, f"Enrolled Activities: {activity_line}")

    y -= 18 * mm

    # ---- Itemized table ----
    table_top = y
    col_desc = margin + 3 * mm
    col_period_x = width - margin - 65 * mm
    col_amount_x = width - margin - 3 * mm

    row_h = 9 * mm
    header_row_h = 9 * mm

    c.setFillColor(BRAND_YELLOW)
    c.rect(margin, y - header_row_h, width - 2 * margin, header_row_h, fill=True, stroke=False)
    c.setFillColor(TEXT_DARK)
    c.setFont("Helvetica-Bold", 9.5)
    c.drawString(col_desc, y - 6 * mm, "Description")
    c.drawString(col_period_x, y - 6 * mm, "Billing Period")
    c.drawRightString(col_amount_x, y - 6 * mm, "Amount")
    y -= header_row_h

    line_items = [(f"Fee Payment - {activity_line}", f"{month:02d}/{year}", amount_paid)]
    c.setFont("Helvetica", 9.5)
    for desc, period, amt in line_items:
        c.setFillColor(TEXT_DARK)
        c.drawString(col_desc, y - 6 * mm, desc[:60])
        c.drawString(col_period_x, y - 6 * mm, period)
        c.drawRightString(col_amount_x, y - 6 * mm, f"Rs {amt}")
        y -= row_h

    c.setStrokeColor(BORDER_GREY)
    c.setLineWidth(0.6)
    c.rect(margin, y, width - 2 * margin, table_top - y, fill=False, stroke=True)
    c.line(margin, table_top - header_row_h, width - margin, table_top - header_row_h)

    y -= 6 * mm

    # ---- Totals ----
    totals_x_label = width - margin - 65 * mm
    subtotal = amount_paid

    c.setFont("Helvetica", 10)
    c.setFillColor(TEXT_MUTED)
    c.drawString(totals_x_label, y, "Sub Total")
    c.setFillColor(TEXT_DARK)
    c.drawRightString(col_amount_x, y, f"Rs {subtotal}")
    y -= 7 * mm

    balance_color = RED if balance_amount and balance_amount > 0 else GREEN
    c.setFillColor(TEXT_MUTED)
    c.drawString(totals_x_label, y, "Balance Due")
    c.setFillColor(balance_color)
    c.drawRightString(col_amount_x, y, f"Rs {balance_amount}")
    y -= 9 * mm

    total_band_h = 10 * mm
    c.setFillColor(BRAND_ORANGE)
    c.rect(totals_x_label - 3 * mm, y - total_band_h + 3 * mm, (col_amount_x - totals_x_label) + 6 * mm, total_band_h, fill=True, stroke=False)
    c.setFillColor(colors.white)
    c.setFont("Helvetica-Bold", 12)
    c.drawString(totals_x_label, y - 3 * mm, "TOTAL PAID")
    c.drawRightString(col_amount_x, y - 3 * mm, f"Rs {amount_paid}")
    y -= total_band_h + 10 * mm

    # ---- Payment mode ----
    c.setFont("Helvetica", 9.5)
    c.setFillColor(TEXT_MUTED)
    c.drawString(margin, y, "Payment Mode:")
    c.setFillColor(TEXT_DARK)
    c.setFont("Helvetica-Bold", 9.5)
    c.drawString(margin + 32 * mm, y, payment_mode)
    y -= 14 * mm

    # ---- Footer: payment terms / signature ----
    c.setStrokeColor(BORDER_GREY)
    c.line(margin, y, width - margin, y)
    y -= 8 * mm

    c.setFont("Helvetica-Bold", 9.5)
    c.setFillColor(TEXT_DARK)
    c.drawString(margin, y, "Notes")
    c.drawString(margin + col_w + 10 * mm, y, "Authorized Signature")
    y -= 6 * mm

    c.setFont("Helvetica", 8.5)
    c.setFillColor(TEXT_MUTED)
    c.drawString(margin, y, "This receipt is system-generated and confirms fee payment.")
    y -= 4.5 * mm
    c.drawString(margin, y, "Retain this receipt for your records.")

    sig_note = f"Approved by: {approved_by}" if approved_by else "Approved by academy admin"
    c.setFont("Helvetica-Oblique", 9)
    c.drawString(margin + col_w + 10 * mm, y + 4.5 * mm, sig_note)
    c.setStrokeColor(TEXT_MUTED)
    c.setLineWidth(0.6)
    c.line(margin + col_w + 10 * mm, y - 1 * mm, margin + col_w + 10 * mm + 45 * mm, y - 1 * mm)

    # ---- Bottom brand bar ----
    c.setFillColor(BRAND_ORANGE)
    c.rect(0, 0, width, 6 * mm, fill=True, stroke=False)

    c.showPage()
    c.save()
    return buf.getvalue()
