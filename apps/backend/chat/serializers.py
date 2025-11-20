from django.contrib.auth import get_user_model
from rest_framework import serializers

from .models import Conversation, Message, Profile


class UserSummarySerializer(serializers.ModelSerializer):
    display_name = serializers.CharField(
        source="profile.display_name", read_only=True, default=""
    )
    avatar_color = serializers.CharField(
        source="profile.avatar_color", read_only=True, default=""
    )

    class Meta:
        model = get_user_model()
        fields = ("id", "username", "display_name", "avatar_color")


class ConversationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Conversation
        fields = ("id", "title", "is_group", "created_at", "updated_at")


class MessageSerializer(serializers.ModelSerializer):
    sender = UserSummarySerializer(read_only=True)

    class Meta:
        model = Message
        fields = ("id", "conversation", "sender", "content", "created_at")
        read_only_fields = ("id", "conversation", "sender", "created_at")


class ProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = Profile
        fields = ("display_name", "ref_code", "avatar_color")
        read_only_fields = ("ref_code",)
