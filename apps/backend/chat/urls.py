from django.urls import path

from . import views


urlpatterns = [
    path("health/", views.health, name="health"),
    path("messages/", views.list_messages, name="messages"),
]

