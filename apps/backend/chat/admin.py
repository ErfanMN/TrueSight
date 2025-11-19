from django.contrib import admin

from .models import Conversation, ConversationMember, Message


@admin.register(Conversation)
class ConversationAdmin(admin.ModelAdmin):
    list_display = ("id", "title", "is_group", "created_at", "updated_at")
    search_fields = ("title",)
    list_filter = ("is_group",)


@admin.register(ConversationMember)
class ConversationMemberAdmin(admin.ModelAdmin):
    list_display = ("id", "conversation", "user", "is_admin", "joined_at")
    list_filter = ("is_admin",)
    search_fields = ("conversation__title", "user__username", "user__email")


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ("id", "conversation", "sender", "short_content", "created_at")
    search_fields = ("content", "conversation__title", "sender__username")
    list_filter = ("created_at",)

    def short_content(self, obj):
        return (obj.content[:50] + "…") if len(obj.content) > 50 else obj.content

    short_content.short_description = "Content"
