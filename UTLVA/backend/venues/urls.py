from rest_framework.routers import DefaultRouter
from .views import BuildingViewSet, VenueViewSet

router = DefaultRouter()
router.register('buildings', BuildingViewSet, basename='building')
router.register('venues', VenueViewSet, basename='venue')

urlpatterns = router.urls
