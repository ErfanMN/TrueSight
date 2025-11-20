from datetime import datetime, timedelta, timezone
import random
import string

from django.contrib.auth import get_user_model
from django.core.mail import send_mail
from django.shortcuts import get_object_or_404
from django.utils import timezone as dj_timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from .models import Conversation, ConversationMember, LoginCode, Message, Profile
from .serializers import ConversationSerializer, MessageSerializer, ProfileSerializer


@api_view(["GET"])
@permission_classes([AllowAny])
def health(request):
    return Response(
        {
            "status": "ok",
            "service": "truesight-chat-backend",
            "time": datetime.now(timezone.utc).isoformat(),
        }
    )


@api_view(["GET"])
@permission_classes([AllowAny])
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


@api_view(["POST"])
@permission_classes([AllowAny])
def request_login_code(request):
    """
    Request a 4-character alphanumeric login code sent to the given email.
    In development the email is printed to the console (console email backend).
    """

    email = (request.data.get("email") or "").strip().lower()
    if not email:
        return Response(
            {"detail": "email is required"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    User = get_user_model()
    local_part = email.split("@", 1)[0] if "@" in email else email
    user, _ = User.objects.get_or_create(
        email=email,
        defaults={"username": local_part},
    )
    if not user.email:
        user.email = email
        user.save(update_fields=["email"])

    code = "".join(random.choices(string.ascii_uppercase + string.digits, k=4))
    expires_at = dj_timezone.now() + timedelta(minutes=10)
    LoginCode.objects.create(user=user, code=code, expires_at=expires_at)

    send_mail(
        subject="Your TrueSight Chat login code",
        message=f"Your login code is: {code}\nThis code expires in 10 minutes.",
        from_email=None,
        recipient_list=[email],
    )

    return Response({"detail": "Login code sent."})


@api_view(["POST"])
@permission_classes([AllowAny])
def verify_login_code(request):
    """
    Verify the login code and return an auth token.
    """

    email = (request.data.get("email") or "").strip().lower()
    code = (request.data.get("code") or "").strip().upper()

    if not email or not code:
        return Response(
            {"detail": "email and code are required"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    User = get_user_model()
    try:
        user = User.objects.get(email=email)
    except User.DoesNotExist:
        return Response(
            {"detail": "Invalid email or code"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    now = dj_timezone.now()
    login_code = (
        LoginCode.objects.filter(
            user=user,
            code__iexact=code,
            is_used=False,
            expires_at__gte=now,
        )
        .order_by("-created_at")
        .first()
    )

    if login_code is None:
        return Response(
            {"detail": "Invalid or expired code"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    login_code.is_used = True
    login_code.save(update_fields=["is_used"])

    # Normalise username to avoid leaking email addresses.
    if "@" in (user.username or ""):
        local_part = user.username.split("@", 1)[0]
        user.username = local_part
        user.save(update_fields=["username"])

    # Ensure the user has a short reference code profile
    profile, created = Profile.objects.get_or_create(user=user)
    if created or not profile.ref_code:
        # Generate a random 6-character alphanumeric code, unique across profiles
        alphabet = string.ascii_uppercase + string.digits
        while True:
            candidate = "".join(random.choices(alphabet, k=6))
            if not Profile.objects.filter(ref_code=candidate).exists():
                profile.ref_code = candidate
                profile.save(update_fields=["ref_code"])
                break

    token, _ = Token.objects.get_or_create(user=user)

    user_payload = {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "ref_code": profile.ref_code,
        "display_name": profile.display_name or "",
        "avatar_color": profile.avatar_color or "",
    }

    return Response({"token": token.key, "user": user_payload})


@api_view(["GET"])
def list_conversations(request):
    """
    List conversations for the current authenticated user.
    """

    qs = (
        Conversation.objects.filter(memberships__user=request.user)
        .distinct()
        .order_by("-updated_at")
        .prefetch_related("memberships__user__profile")
    )
    serializer = ConversationSerializer(qs, many=True)
    data = serializer.data

    # For 1:1 conversations, show the "other" participant's name as title
    # on a per-user basis, and avoid leaking emails.
    conversations_by_id = {conv.id: conv for conv in qs}
    for item in data:
        conv_id = item.get("id")
        conv = conversations_by_id.get(conv_id)
        if conv and not conv.is_group:
            others = [
                m.user
                for m in conv.memberships.all()
                if m.user_id != request.user.id
            ]
            other_user = others[0] if others else request.user
            profile = getattr(other_user, "profile", None)
            display_label = (
                (getattr(profile, "display_name", "") or "").strip()
                or (other_user.username or "").strip()
                or "User"
            )
            item["title"] = display_label
        # As a last resort, trim any accidental emails.
        title = item.get("title") or ""
        if "@" in title:
            item["title"] = title.split("@", 1)[0]

    return Response({"results": data})


@api_view(["GET", "PATCH"])
def me_profile(request):
    """
    Retrieve or update the authenticated user's profile.
    """

    profile, _ = Profile.objects.get_or_create(user=request.user)

    if request.method == "GET":
        serializer = ProfileSerializer(profile)
        data = serializer.data
        data["email"] = request.user.email
        data["user_id"] = request.user.id
        return Response(data)

    serializer = ProfileSerializer(profile, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response(serializer.data)


@api_view(["POST"])
def start_conversation_by_ref_code(request):
    """
    Create (or reuse) a 1:1 conversation with another user by their ref_code.
    """

    raw_code = (request.data.get("ref_code") or "").strip().upper()
    if not raw_code:
        return Response(
            {"detail": "ref_code is required"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        target_profile = Profile.objects.select_related("user").get(
            ref_code__iexact=raw_code
        )
    except Profile.DoesNotExist:
        return Response(
            {"detail": "No user found with this code"},
            status=status.HTTP_404_NOT_FOUND,
        )

    target_user = target_profile.user
    if target_user == request.user:
        return Response(
            {"detail": "You cannot start a conversation with yourself"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    # Try to find an existing direct conversation between the two users.
    conv_qs = (
        Conversation.objects.filter(is_group=False)
        .filter(memberships__user=request.user)
        .filter(memberships__user=target_user)
        .distinct()
    )
    conversation = conv_qs.first()

    if conversation is None:
        # Create a new conversation and add both users.
        display_label = (
            target_profile.display_name or target_user.username or "User"
        )
        conversation = Conversation.objects.create(
            title=display_label, is_group=False
        )
        ConversationMember.objects.bulk_create(
            [
                ConversationMember(conversation=conversation, user=request.user),
                ConversationMember(conversation=conversation, user=target_user),
            ],
            ignore_conflicts=True,
        )

    serializer = ConversationSerializer(conversation)
    return Response(serializer.data, status=status.HTTP_201_CREATED)


@api_view(["GET", "POST"])
def conversation_messages(request, conversation_id: int):
    """
    GET: List messages in a conversation.
         Supports optional ?limit=... (default 50, max 200).
    POST: Append a new message with {"content": "..."} for the current user.
    """

    conversation = get_object_or_404(Conversation, id=conversation_id)

    # Ensure the user is a member; auto-add for now.
    ConversationMember.objects.get_or_create(
        conversation=conversation,
        user=request.user,
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
        sender=request.user,
        content=content,
    )

    # Touch conversation updated_at
    Conversation.objects.filter(pk=conversation.pk).update(
        updated_at=dj_timezone.now()
    )

    serializer = MessageSerializer(message)
    return Response(serializer.data, status=status.HTTP_201_CREATED)
