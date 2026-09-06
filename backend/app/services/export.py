import csv
import io
from typing import List, Sequence

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import cm

BRAND_BLUE = colors.HexColor("#0000FF")
BRAND_LIGHT = colors.HexColor("#F0F8FF")
BRAND_ORANGE = colors.HexColor("#FFA500")
BRAND_YELLOW = colors.HexColor("#FFF500")
BRAND_ALICE_BLUE = colors.HexColor("#F0F8FF")


def rows_to_csv(headers: Sequence[str], rows: Sequence[Sequence]) -> io.BytesIO:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(headers)
    writer.writerows(rows)
    byte_buffer = io.BytesIO(buffer.getvalue().encode("utf-8"))
    byte_buffer.seek(0)
    return byte_buffer


def rows_to_pdf(title: str, headers: Sequence[str], rows: Sequence[Sequence]) -> io.BytesIO:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, topMargin=1.5 * cm, bottomMargin=1.5 * cm)
    styles = getSampleStyleSheet()
    title_style = styles["Title"]
    title_style.textColor = BRAND_BLUE

    elements = [Paragraph(title, title_style), Spacer(1, 0.5 * cm)]

    data: List[List] = [list(headers)] + [list(map(str, row)) for row in rows]
    table = Table(data, repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), BRAND_BLUE),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, BRAND_LIGHT]),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ]
        )
    )
    elements.append(table)
    doc.build(elements)
    buffer.seek(0)
    return buffer


def build_coach_monthly_report_pdf(
    *,
    coach_name: str,
    month: int,
    year: int,
    sections: Sequence[dict],
) -> io.BytesIO:
    """Monthly report of a coach's students, grouped by activity, with attendance & fee status."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, topMargin=1.5 * cm, bottomMargin=1.5 * cm)
    styles = getSampleStyleSheet()
    title_style = styles["Title"]
    title_style.textColor = BRAND_ORANGE
    heading_style = styles["Heading3"]
    heading_style.textColor = colors.HexColor("#CC7000")

    month_names = ["", "January", "February", "March", "April", "May", "June", "July", "August",
                   "September", "October", "November", "December"]
    elements = [
        Paragraph(f"Monthly Report - {coach_name}", title_style),
        Paragraph(f"{month_names[month]} {year}", styles["Normal"]),
        Spacer(1, 0.6 * cm),
    ]

    headers = ["Student", "Classes", "Present", "Absent", "Leave", "Attendance %", "Fee Status", "Fee Amount"]

    if not sections:
        elements.append(Paragraph("No classes conducted this month.", styles["Normal"]))

    for section in sections:
        elements.append(Paragraph(section["activity_name"], heading_style))
        rows = [headers]
        if not section["students"]:
            elements.append(Paragraph("No student attendance recorded.", styles["Normal"]))
            elements.append(Spacer(1, 0.4 * cm))
            continue
        for s in section["students"]:
            rows.append(
                [
                    s["name"],
                    s["total"],
                    s["present"],
                    s["absent"],
                    s["leave"],
                    f"{s['attendance_pct']}%",
                    s["fee_status"],
                    f"Rs {s['fee_amount']}",
                ]
            )
        table = Table(rows, repeatRows=1)
        table.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), BRAND_ORANGE),
                    ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                    ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                    ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, BRAND_ALICE_BLUE]),
                    ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
                    ("FONTSIZE", (0, 0), (-1, -1), 8),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ]
            )
        )
        elements.append(table)
        elements.append(Spacer(1, 0.6 * cm))

    doc.build(elements)
    buffer.seek(0)
    return buffer
