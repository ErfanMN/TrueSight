from django.contrib.auth import get_user_model
from rest_framework import serializers

from .models import Conversation, ConversationMember, Message, Profile


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
    is_mine = serializers.SerializerMethodField()
    read_by_all = serializers.SerializerMethodField()

    class Meta:
        model = Message
        fields = (
            "id",
            "conversation",
            "sender",
            "content",
            "created_at",
            "is_mine",
            "read_by_all",
        )
        read_only_fields = (
            "id",
            "conversation",
            "sender",
            "created_at",
            "is_mine",
            "read_by_all",
        )

    def get_is_mine(self, obj) -> bool:
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not getattr(user, "is_authenticated", False):
            return False
        return obj.sender_id == user.id

    def get_read_by_all(self, obj) -> bool:
        mapping = self.context.get("read_by_all_map") or {}
        return bool(mapping.get(obj.id))


class ProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = Profile
        fields = ("display_name", "ref_code", "avatar_color")
        read_only_fields = ("ref_code",)
