import base64
import io
import unittest
from datetime import date, time
from decimal import Decimal
from unittest.mock import patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from PIL import Image
from app.database import Base, get_db
from app.models import User, UserRole, Activity, CoachActivity, StudentEnrollment, ClassSession, StudentAttendance, AttendanceStatus, StudentFee, FeeStatus, CoachAttendance, CoachAttendanceStatus
from app.routers import fees, students, receipts, reports, activities, coaches
from app.security import require_admin, require_coach, require_admin_or_coach, get_current_user
from app.models.user import UserDetails

class RequestedChanges(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()
        self.admin = User(name="Admin", email="admin@example.com", role=UserRole.ADMIN, password_hash="unused")
        self.coach = User(name="Coach", email="coach@example.com", role=UserRole.COACH, password_hash="unused")
        self.yoga = Activity(name="Yoga")
        self.dance = Activity(name="Dance")
        self.s1 = User(name="Yoga Student", email="yoga@example.com", role=UserRole.STUDENT, password_hash="unused", phone="1234567890", phone_secondary="0987654321")
        self.s2 = User(name="Dance Student", email="dance@example.com", role=UserRole.STUDENT, password_hash="unused")
        self.db.add_all([self.admin, self.coach, self.yoga, self.dance, self.s1, self.s2]); self.db.flush()
        self.db.add_all([StudentEnrollment(student_id=self.s1.id, activity_id=self.yoga.id), StudentEnrollment(student_id=self.s2.id, activity_id=self.dance.id), CoachActivity(coach_id=self.coach.id, activity_id=self.yoga.id)])
        self.cls = ClassSession(activity_id=self.yoga.id, coach_id=self.coach.id, date=date(2026,9,10), start_time=time(9), end_time=time(10))
        self.db.add(self.cls); self.db.commit()
        self.app = FastAPI()
        for router in [fees.router, students.router, receipts.router, reports.router, activities.router, coaches.router]: self.app.include_router(router)
        self.app.dependency_overrides[get_db] = lambda: self.db
        self.app.dependency_overrides[require_admin] = lambda: self.admin
        self.app.dependency_overrides[require_coach] = lambda: self.coach
        self.app.dependency_overrides[require_admin_or_coach] = lambda: self.admin
        self.app.dependency_overrides[get_current_user] = lambda: self.admin
        self.client = TestClient(self.app)
        self.patches = [patch("app.routers.receipts.notify_and_push"), patch("app.routers.receipts.notify"), patch("app.routers.fees.notify")]
        for p in self.patches: p.start()
    def tearDown(self):
        for p in self.patches: p.stop()
        self.db.close(); self.engine.dispose()
    def test_activity_filter_and_contacts(self):
        result = self.client.get("/students", params={"activity_id": self.yoga.id}).json()
        self.assertEqual([r['id'] for r in result], [self.s1.id])
        self.assertEqual(result[0]['activities'][0]['name'], 'Yoga')
        roster = self.client.get(f"/activities/{self.yoga.id}/roster").json()
        self.assertEqual(roster[0]['phone'], '1234567890')
        self.assertEqual(roster[0]['phone_secondary'], '0987654321')
    def test_product_invoice_receipt_and_reports(self):
        r = self.client.post('/fees', json={'student_id': self.s1.id, 'month':9, 'year':2026, 'amount':'100', 'product_amount':'25', 'due_date':'2026-09-10'})
        self.assertEqual(r.status_code,201, r.text)
        self.assertEqual(Decimal(r.json()['balance_amount']), Decimal('125'))
        fid = r.json()['id']
        self.client.post('/fees/mark-paid', json={'fee_id':fid})
        pdf = self.client.get(f'/fees/{fid}/receipt')
        self.assertTrue(pdf.content.startswith(b'%PDF'))
        csv = self.client.get(f'/fees/{fid}/receipt', params={'fmt':'csv'}).text
        self.assertIn('Product Amount',csv); self.assertIn('125',csv)
        self.db.add(StudentAttendance(student_id=self.s1.id, class_id=self.cls.id, status=AttendanceStatus.PRESENT)); self.db.commit()
        result = self.client.get('/reports', params={'month':9,'year':2026}).json()
        self.assertEqual(Decimal(result['total_revenue']), Decimal('125'))
        self.assertEqual(result['activities'][0]['present'],1)
        self.assertEqual(self.client.get('/reports',params={'month':8,'year':2026}).json()['total_revenue'],0)
        for kind in ['students','attendance','revenue']:
            r = self.client.get('/reports',params={'month':9,'year':2026,'kind':kind,'fmt':'pdf'})
            self.assertTrue(r.content.startswith(b'%PDF'),r.text)
    def test_coach_reports_include_fee_ledger_for_assigned_students_only(self):
        assigned_paid = StudentFee(student_id=self.s1.id, month=9, year=2026, amount=Decimal('100'), product_amount=Decimal('20'), balance_amount=Decimal('0'), status=FeeStatus.PAID, due_date=date(2026,9,10))
        assigned_pending_student = User(name="Second Yoga Student", email="yoga2@example.com", role=UserRole.STUDENT, password_hash="unused")
        self.db.add(assigned_pending_student); self.db.flush()
        self.db.add(StudentEnrollment(student_id=assigned_pending_student.id, activity_id=self.yoga.id))
        assigned_pending = StudentFee(student_id=assigned_pending_student.id, month=9, year=2026, amount=Decimal('150'), product_amount=Decimal('0'), balance_amount=Decimal('50'), status=FeeStatus.UNPAID, due_date=date(2026,9,10))
        other_student_fee = StudentFee(student_id=self.s2.id, month=9, year=2026, amount=Decimal('900'), product_amount=Decimal('0'), balance_amount=Decimal('900'), status=FeeStatus.UNPAID, due_date=date(2026,9,10))
        self.db.add_all([assigned_paid, assigned_pending, other_student_fee])
        self.db.add(StudentAttendance(student_id=self.s1.id, class_id=self.cls.id, status=AttendanceStatus.PRESENT, coach_id=self.coach.id))
        self.db.commit()
        self.app.dependency_overrides[require_admin_or_coach] = lambda: self.coach
        rendered = {}
        def capture_pdf(title, headers, rows):
            rendered.update(title=title, headers=headers, rows=rows)
            return io.BytesIO(b"%PDF-test")
        with patch("app.routers.reports.rows_to_pdf", side_effect=capture_pdf):
            detail_response = self.client.get('/reports', params={'month':9,'year':2026,'day':10,'kind':'classes_detail','fmt':'pdf'})
        self.assertEqual(detail_response.content, b"%PDF-test")
        self.assertEqual(rendered['headers'], ["Class Time", "Activity", "Student", "Status", "Approval"])
        self.assertIn(["09:00 - 10:00", "Yoga", "Yoga Student", "PRESENT", "PENDING"], rendered['rows'])
        self.assertEqual(rendered['rows'][-1], ["Total classes", 1, "Student attendance records", 1, ""])
        report = self.client.get('/reports', params={'month':9,'year':2026}).json()
        self.assertEqual(Decimal(report['fee_paid_total']), Decimal('120'))
        self.assertEqual(Decimal(report['fee_pending_total']), Decimal('50'))
        self.assertEqual(report['fee_paid_count'], 1)
        self.assertEqual(report['fee_pending_count'], 1)
        self.assertEqual(report['classes_done'], 1)
        for kind in ['students_summary','classes','classes_detail','fees_paid','fees_pending']:
            response = self.client.get('/reports', params={'month':9,'year':2026,'kind':kind,'fmt':'pdf'})
            self.assertTrue(response.content.startswith(b'%PDF'), response.text)
        detail = self.client.get('/reports', params={'month':9,'year':2026,'day':10,'kind':'classes_detail','fmt':'pdf'})
        self.assertTrue(detail.content.startswith(b'%PDF'), detail.text)
        self.assertIn('2026-09-10', detail.headers['content-disposition'])
    def test_coach_attendance_date_filter(self):
        self.db.add_all([
            CoachAttendance(coach_id=self.coach.id, date=date(2026, 9, 10), status=CoachAttendanceStatus.PRESENT),
            CoachAttendance(coach_id=self.coach.id, date=date(2026, 10, 6), status=CoachAttendanceStatus.ABSENT),
        ])
        self.db.commit()
        response = self.client.get(f'/coaches/{self.coach.id}/attendance', params={'date_from':'2026-10-01','date_to':'2026-10-31'})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual([row['date'][:10] for row in response.json()], ['2026-10-06'])
    def test_dated_receipts_and_multiple_collections(self):
        payload = {'student_id':self.s1.id,'month':9,'year':2026,'amount':'100','product_amount':'25','billing_date':'2026-09-10'}
        for day in [10,11]:
            payload['billing_date'] = f'2026-09-{day}'
            r = self.client.post('/receipts',json=payload)
            self.assertEqual(r.status_code,201,r.text)
            rid = r.json()['id']
            self.assertEqual(self.client.put(f'/receipts/{rid}/approve',json={}).status_code,200)
            self.assertEqual(self.client.put(f'/receipts/{rid}/approve',json={}).status_code,400)
            self.assertTrue(self.client.get(f'/receipts/{rid}/pdf').content.startswith(b'%PDF'))
        fee = self.db.query(StudentFee).one()
        self.assertEqual(fee.amount + fee.product_amount,Decimal('250'))
        payload['billing_date']='2026-08-10'
        self.assertEqual(self.client.post('/receipts',json=payload).status_code,400)
        payload['amount']='-1'
        self.assertEqual(self.client.post('/receipts',json=payload).status_code,422)
    def test_approval_does_not_duplicate_invoiced_products(self):
        invoice = self.client.post('/fees', json={'student_id': self.s1.id, 'month':9, 'year':2026, 'amount':'100', 'product_amount':'25', 'due_date':'2026-09-10'}).json()
        receipt = self.client.post('/receipts',json={'student_id':self.s1.id,'month':9,'year':2026,'amount':'100','product_amount':'25'}).json()
        result = self.client.put(f"/receipts/{receipt['id']}/approve",json={})
        self.assertEqual(result.status_code,200,result.text)
        fee = self.db.query(StudentFee).filter_by(id=invoice['id']).one()
        self.assertEqual(fee.product_amount,Decimal('25'))
        self.assertEqual(fee.balance_amount,Decimal('0'))
        self.assertEqual(fee.amount + fee.product_amount,Decimal('125'))

    def test_coach_photo_to_admin(self):
        image = io.BytesIO(); Image.new('RGB',(20,20),'red').save(image,format='JPEG')
        r = self.client.post(f'/activities/classes/{self.cls.id}/group-photo', json={'photo_base64':base64.b64encode(image.getvalue()).decode()})
        self.assertEqual(r.status_code,200,r.text)
        self.assertTrue(r.json()['has_group_photo'])
        gallery = self.client.get('/activities/session-photos')
        self.assertEqual(gallery.status_code, 200, gallery.text)
        self.assertEqual(gallery.json()[0]['class_id'], self.cls.id)
        self.assertEqual(gallery.json()[0]['activity_name'], 'Yoga')
        r = self.client.get(f'/activities/classes/{self.cls.id}/group-photo')
        self.assertEqual(r.status_code,200); self.assertEqual(r.headers['content-type'],'image/jpeg')
        other_coach = User(name="Other Coach", email="other@example.com", role=UserRole.COACH, password_hash="unused")
        self.db.add(other_coach); self.db.flush()
        other_class = ClassSession(activity_id=self.yoga.id, coach_id=other_coach.id, date=date(2026,9,11), start_time=time(9), end_time=time(10), group_photo=image.getvalue())
        self.db.add(other_class); self.db.commit()
        self.app.dependency_overrides[get_current_user] = lambda: self.coach
        coach_gallery = self.client.get('/activities/session-photos')
        self.assertEqual(coach_gallery.status_code, 200)
        self.assertEqual([p['class_id'] for p in coach_gallery.json()], [self.cls.id])
        self.assertEqual(self.client.get(f'/activities/classes/{other_class.id}/group-photo').status_code, 403)
        self.assertEqual(self.client.delete(f'/activities/classes/{other_class.id}/group-photo').status_code, 403)
        self.assertEqual(self.client.delete(f'/activities/classes/{self.cls.id}/group-photo').status_code, 204)
        self.assertEqual(self.client.get('/activities/session-photos').json(), [])
        self.app.dependency_overrides[get_current_user] = lambda: self.admin
        self.assertEqual(self.client.get('/activities/session-photos').json()[0]['class_id'], other_class.id)
        self.assertEqual(self.client.delete(f'/activities/classes/{other_class.id}/group-photo').status_code, 204)
        self.assertEqual(self.client.get(f'/activities/classes/{other_class.id}/group-photo').status_code, 404)
        self.app.dependency_overrides[get_current_user] = lambda: self.s2
        self.assertEqual(self.client.get('/activities/session-photos').status_code, 403)
        self.assertEqual(self.client.get(f'/activities/classes/{self.cls.id}/group-photo').status_code,404)

    def test_student_photo_delete_and_coach_scope(self):
        self.db.add_all([
            UserDetails(user_id=self.s1.id, profile_photo=b"student-photo"),
            UserDetails(user_id=self.s2.id, profile_photo=b"other-activity-photo"),
        ])
        self.db.commit()
        self.app.dependency_overrides[require_admin_or_coach] = lambda: self.coach
        self.assertEqual(self.client.delete(f"/students/{self.s2.id}/photo").status_code, 403)
        self.assertEqual(self.client.delete(f"/students/{self.s1.id}/photo").status_code, 204)
        self.assertEqual(self.client.get(f"/students/{self.s1.id}/photo").status_code, 404)
        self.assertEqual(self.client.delete(f"/students/{self.s1.id}/photo").status_code, 404)
        self.assertIsNotNone(self.db.query(User).filter_by(id=self.s1.id).first())

if __name__ == '__main__': unittest.main()
