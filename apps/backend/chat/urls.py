from django.urls import path

from . import views


urlpatterns = [
    path("health/", views.health, name="health"),
    path("messages/", views.list_messages, name="messages"),
    path("auth/request-code/", views.request_login_code, name="request_login_code"),
    path("auth/verify-code/", views.verify_login_code, name="verify_login_code"),
    path("conversations/", views.list_conversations, name="list_conversations"),
    path(
        "conversations/start/",
        views.start_conversation_by_ref_code,
        name="start_conversation_by_ref_code",
    ),
    path(
        "conversations/<int:conversation_id>/messages/",
        views.conversation_messages,
        name="conversation_messages",
    ),
]
