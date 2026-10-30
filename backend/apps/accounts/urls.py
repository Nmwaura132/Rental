from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    CaretakerListView,
    ChangePasswordView,
    CodeLoginView,
    LoginCodeView,
    LoginView,
    PasswordResetRequestView,
    PasswordResetView,
    ProfileView,
    RegisterView,
    SignupCodeView,
    SignupView,
    TenantListView,
    TenantRemovalView,
    UploadIdPhotoView,
)

urlpatterns = [
    path("register/", RegisterView.as_view(), name="register"),
    # A landlord signing themselves up; tenants are still added by landlords.
    path("signup/request-code/", SignupCodeView.as_view(), name="signup-request-code"),
    path("signup/", SignupView.as_view(), name="signup"),
    path("login/", LoginView.as_view(), name="login"),
    path("login/request-code/", LoginCodeView.as_view(), name="login-request-code"),
    path("login/code/", CodeLoginView.as_view(), name="login-code"),
    path("token/refresh/", TokenRefreshView.as_view(), name="token-refresh"),
    path("profile/", ProfileView.as_view(), name="profile"),
    path("change-password/", ChangePasswordView.as_view(), name="change-password"),
    path("password-reset/request/", PasswordResetRequestView.as_view(), name="password-reset-request"),
    path("password-reset/", PasswordResetView.as_view(), name="password-reset"),
    path("tenants/", TenantListView.as_view(), name="tenant-list"),
    path("tenants/<int:pk>/", TenantRemovalView.as_view(), name="tenant-remove"),
    path("caretakers/", CaretakerListView.as_view(), name="caretaker-list"),
    path("upload-id/", UploadIdPhotoView.as_view(), name="upload-id"),
]
