from datetime import datetime, timezone

from django.contrib.auth import get_user_model
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from .models import Conversation, ConversationMember, Message
from .serializers import ConversationSerializer, MessageSerializer


def _get_demo_user():
    """
    Temporary helper until real authentication is wired.
    This ensures API behaviour is predictable during early development.
    """

    User = get_user_model()
    user, _ = User.objects.get_or_create(username="demo")
    return user


@api_view(["GET"])
def health(request):
    return Response(
        {
            "status": "ok",
            "service": "truesight-chat-backend",
            "time": datetime.now(timezone.utc).isoformat(),
        }
    )


@api_view(["GET"])
def list_messages(request):
    """
    Legacy dummy endpoint kept for quick connectivity tests.
    """

    messages = [
        {
            "id": 1,
            "sender": "system",
            "text": "Welcome to TrueSight Chat.",
            "sent_at": datetime.now(timezone.utc).isoformat(),
        },
        {
            "id": 2,
            "sender": "system",
            "text": "This is dummy data from Django.",
            "sent_at": datetime.now(timezone.utc).isoformat(),
        },
    ]
    return Response({"results": messages})


@api_view(["GET"])
def list_conversations(request):
    """
    List conversations for the current (demo) user.
    """

    user = _get_demo_user()
    qs = (
        Conversation.objects.filter(memberships__user=user)
        .distinct()
        .order_by("-updated_at")
    )
    serializer = ConversationSerializer(qs, many=True)
    return Response({"results": serializer.data})


@api_view(["GET", "POST"])
def conversation_messages(request, conversation_id: int):
    """
    GET: List messages in a conversation.
         Supports optional ?limit=... (default 50, max 200).
    POST: Append a new message with {"content": "..."}.
    """

    user = _get_demo_user()
    conversation = get_object_or_404(Conversation, id=conversation_id)

    # Ensure the user is a member; auto-add for now.
    ConversationMember.objects.get_or_create(
        conversation=conversation,
        user=user,
    )

    if request.method == "GET":
        try:
            limit = int(request.query_params.get("limit", 50))
        except (TypeError, ValueError):
            limit = 50
        limit = max(1, min(limit, 200))

        messages_qs = (
            Message.objects.filter(conversation=conversation)
            .order_by("-created_at")[:limit]
        )
        # Return oldest-to-newest within the window
        messages_qs = list(messages_qs)[::-1]
        serializer = MessageSerializer(messages_qs, many=True)
        return Response({"results": serializer.data})

    # POST: create new message
    content = request.data.get("content", "").strip()
    if not content:
        return Response(
            {"detail": "content is required"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    message = Message.objects.create(
     conversation=conversation,
        sender=user,
        content=content,
    )

    # Touch conversation updated_at
    Conversation.objects.filter(pk=conversation.pk).update(
        updated_at=datetime.now(timezone.utc)
    )

    serializer = MessageSerializer(message)
    return Response(serializer.data, status=status.HTTP_201_CREATED)
