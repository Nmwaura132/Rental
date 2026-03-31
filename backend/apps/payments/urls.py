from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import InvoiceViewSet, PaymentViewSet, MpesaC2BValidateView, MpesaC2BConfirmView, DashboardStatsView

router = DefaultRouter()
router.register("invoices", InvoiceViewSet, basename="invoice")
router.register("", PaymentViewSet, basename="payment")

urlpatterns = [
    path("dashboard/", DashboardStatsView.as_view(), name="dashboard-stats"),
    path("mpesa/validate/", MpesaC2BValidateView.as_view(), name="mpesa-validate"),
    path("mpesa/confirm/", MpesaC2BConfirmView.as_view(), name="mpesa-confirm"),
    path("", include(router.urls)),
]
