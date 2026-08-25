from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    InvoiceViewSet, PaymentViewSet,
    MpesaRegisterC2BView,
    MpesaC2BValidateView, MpesaC2BConfirmView,
    MpesaSTKPushView, MpesaSTKCallbackView, MpesaSTKStatusView,
    DashboardStatsView,
)
from .bank_views import (
    KCBIPNView,
    EquityIPNView,
    EquityStatementPollView,
    BankNotificationListView,
    BankNotificationMatchView,
)
from .report_views import ReportsView
from .mri_views import MRIStatementView

router = DefaultRouter()
router.register("invoices", InvoiceViewSet, basename="invoice")
router.register("", PaymentViewSet, basename="payment")

urlpatterns = [
    path("dashboard/", DashboardStatsView.as_view(), name="dashboard-stats"),
    path("reports/", ReportsView.as_view(), name="reports"),
    path("mri/", MRIStatementView.as_view(), name="mri-statement"),
    # M-Pesa C2B Paybill — registration + webhooks
    path("mpesa/register/", MpesaRegisterC2BView.as_view(), name="mpesa-register-c2b"),
    path("mpesa/validate/", MpesaC2BValidateView.as_view(), name="mpesa-validate"),
    path("mpesa/confirm/", MpesaC2BConfirmView.as_view(), name="mpesa-confirm"),
    # M-Pesa STK Push
    path("stk/push/", MpesaSTKPushView.as_view(), name="stk-push"),
    path("stk/callback/", MpesaSTKCallbackView.as_view(), name="stk-callback"),
    path("stk/status/", MpesaSTKStatusView.as_view(), name="stk-status"),
    # Bank IPN webhooks
    path("bank/kcb/ipn/", KCBIPNView.as_view(), name="kcb-ipn"),
    path("bank/equity/ipn/", EquityIPNView.as_view(), name="equity-ipn"),
    # Equity statement poll (manual trigger)
    path("bank/equity/poll/", EquityStatementPollView.as_view(), name="equity-poll"),
    # Bank notification management
    path("bank/notifications/", BankNotificationListView.as_view(), name="bank-notifications"),
    path("bank/notifications/<int:pk>/match/", BankNotificationMatchView.as_view(), name="bank-notification-match"),
    path("", include(router.urls)),
]
