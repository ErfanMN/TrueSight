from django.urls import path

from . import views


urlpatterns = [
    path("health/", views.health, name="health"),
    path("messages/", views.list_messages, name="messages"),
    path("conversations/", views.list_conversations, name="list_conversations"),
    path(
        "conversations/<int:conversation_id>/messages/",
        views.conversation_messages,
        name="conversation_messages",
    ),
]
