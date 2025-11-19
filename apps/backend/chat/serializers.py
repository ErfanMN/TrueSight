from django.contrib.auth import get_user_model
from rest_framework import serializers

from .models import Conversation, Message


class UserSummarySerializer(serializers.ModelSerializer):
    class Meta:
        model = get_user_model()
        fields = ("id", "username")


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

