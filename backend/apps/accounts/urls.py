from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    CaretakerListView,
    ChangePasswordView,
    LoginView,
    PasswordResetRequestView,
    PasswordResetView,
    ProfileView,
    RegisterView,
    TenantListView,
    UploadIdPhotoView,
)

urlpatterns = [
    path("register/", RegisterView.as_view(), name="register"),
    path("login/", LoginView.as_view(), name="login"),
    path("token/refresh/", TokenRefreshView.as_view(), name="token-refresh"),
    path("profile/", ProfileView.as_view(), name="profile"),
    path("change-password/", ChangePasswordView.as_view(), name="change-password"),
    path("password-reset/request/", PasswordResetRequestView.as_view(), name="password-reset-request"),
    path("password-reset/", PasswordResetView.as_view(), name="password-reset"),
    path("tenants/", TenantListView.as_view(), name="tenant-list"),
    path("caretakers/", CaretakerListView.as_view(), name="caretaker-list"),
    path("upload-id/", UploadIdPhotoView.as_view(), name="upload-id"),
]
