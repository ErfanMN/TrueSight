from datetime import datetime, timezone

from rest_framework.decorators import api_view
from rest_framework.response import Response


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

# Create your views here.
