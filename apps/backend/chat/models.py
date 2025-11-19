from django.conf import settings
from django.db import models
from django.utils import timezone


class Conversation(models.Model):
    """
    A logical chat channel between 2+ participants.
    For now this is a simple table; in the future you could shard by ID range.
    """

    title = models.CharField(max_length=255, blank=True)
    is_group = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-updated_at"]

    def __str__(self) -> str:
        if self.title:
            return self.title
        return f"Conversation {self.pk}"


class ConversationMember(models.Model):
    """
    Membership of a user in a conversation.
    This lets you support 1:1 and group chats with the same model.
    """

    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name="memberships",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="chat_memberships",
    )
    joined_at = models.DateTimeField(auto_now_add=True)
    is_admin = models.BooleanField(default=False)

    class Meta:
        unique_together = ("conversation", "user")
        ordering = ["joined_at"]

    def __str__(self) -> str:
        return f"{self.user} in {self.conversation}"


class Message(models.Model):
    """
    A single chat message in a conversation.
    """

    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name="messages",
    )
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="chat_messages",
    )
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]
        indexes = [
            models.Index(fields=["conversation", "created_at"]),
        ]

    def __str__(self) -> str:
        return f"Message {self.pk} in {self.conversation}"


class LoginCode(models.Model):
    """
    One-time login code sent to a user's email.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="login_codes",
    )
    code = models.CharField(max_length=8)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user", "created_at"]),
        ]

    def __str__(self) -> str:
        return f"LoginCode({self.user}, {self.code})"

    @property
    def is_expired(self) -> bool:
        return self.expires_at <= timezone.now()


class Profile(models.Model):
    """
    Lightweight per-user profile storing a short reference code.
    """

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="profile",
    )
    ref_code = models.CharField(max_length=6, unique=True)
    display_name = models.CharField(max_length=64, blank=True)
    avatar_color = models.CharField(max_length=7, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["user_id"]

    def __str__(self) -> str:
        return f"Profile({self.user}, {self.ref_code})"
