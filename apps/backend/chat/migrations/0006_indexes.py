from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("chat", "0005_conversationmember_last_read_at_profile_last_seen_at_and_more"),
    ]

    operations = [
        migrations.AddIndex(
            model_name="conversation",
            index=models.Index(
                fields=["updated_at"],
                name="chat_conversation_updated_at_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="message",
            index=models.Index(
                fields=["sender", "created_at"],
                name="chat_message_sender_created_idx",
            ),
        ),
    ]

