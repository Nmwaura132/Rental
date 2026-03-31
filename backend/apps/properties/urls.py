from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import PropertyViewSet, UnitViewSet, PropertyChargeViewSet

router = DefaultRouter()
# units MUST be registered before "" to prevent the empty-prefix detail pattern
# from swallowing "units/" as a property pk
router.register("units", UnitViewSet, basename="unit")
router.register("charges", PropertyChargeViewSet, basename="propertycharge")
router.register("", PropertyViewSet, basename="property")

urlpatterns = [path("", include(router.urls))]
