from django.contrib import admin
from django.urls import path, include
from django.http import JsonResponse


def api_root(request):
    return JsonResponse({
        'system': 'UTLVA API',
        'version': '1.0.0',
        'status': 'running',
    })


urlpatterns = [
    path('', api_root, name='api-root'),
    path('admin/', admin.site.urls),
    path('api/auth/', include('accounts.urls')),
    path('api/academics/', include('academics.urls')),
    path('api/venues/', include('venues.urls')),
    path('api/timetable/', include('timetable.urls')),
    # Phase 8
    path('api/sessions/', include('timetable.sessions_urls')),
    path('api/system/', include('timetable.system_urls')),
]
