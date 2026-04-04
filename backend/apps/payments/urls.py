from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    InvoiceViewSet, PaymentViewSet,
    MpesaC2BValidateView, MpesaC2BConfirmView,
    MpesaSTKPushView, MpesaSTKCallbackView, MpesaSTKStatusView,
    DashboardStatsView,
)
from .report_views import ReportsView

router = DefaultRouter()
router.register("invoices", InvoiceViewSet, basename="invoice")
router.register("", PaymentViewSet, basename="payment")

urlpatterns = [
    path("dashboard/", DashboardStatsView.as_view(), name="dashboard-stats"),
    path("reports/", ReportsView.as_view(), name="reports"),
    # C2B Paybill webhooks
    path("mpesa/validate/", MpesaC2BValidateView.as_view(), name="mpesa-validate"),
    path("mpesa/confirm/", MpesaC2BConfirmView.as_view(), name="mpesa-confirm"),
    # STK Push
    path("stk/push/", MpesaSTKPushView.as_view(), name="stk-push"),
    path("stk/callback/", MpesaSTKCallbackView.as_view(), name="stk-callback"),
    path("stk/status/", MpesaSTKStatusView.as_view(), name="stk-status"),
    path("", include(router.urls)),
]
