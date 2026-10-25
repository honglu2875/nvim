"""Deterministic app-server peer; never calls a model or runs a shell command."""
import json
import os
import sys

log_path = sys.argv[1]
threads = 0
turns = 0
current = None


def emit(value, fragmented=False):
    data = (json.dumps(value, ensure_ascii=False) + "\n").encode()
    if fragmented:
        for offset in range(0, len(data), 7):
            os.write(sys.stdout.fileno(), data[offset : offset + 7])
    else:
        os.write(sys.stdout.fileno(), data)


def reply(message, result):
    emit({"id": message["id"], "result": result})


def event(method, params):
    emit({"method": method, "params": params}, fragmented=True)


def complete(status="completed"):
    thread, turn = current
    event("turn/completed", {"threadId": thread, "turn": {"id": turn, "status": status, "items": [], "error": None}})


for line in sys.stdin:
    message = json.loads(line)
    with open(log_path, "a") as log:
        log.write(json.dumps(message) + "\n")
    method, params = message.get("method"), message.get("params", {})
    if method == "initialize":
        assert params["clientInfo"]["name"] == "personal_nvim_codex"
        reply(message, {"userAgent": "fake-codex/0.164.0"})
    elif method == "initialized":
        pass
    elif method == "thread/start":
        assert os.path.isabs(params["cwd"])
        threads += 1
        reply(message, {"thread": {"id": f"thread-{threads}", "turns": []}})
    elif method == "thread/resume":
        reply(message, {"thread": {"id": params["threadId"], "turns": [
            {"id": "old-turn", "status": "completed", "items": [
                {"id": "old-agent", "type": "agentMessage", "text": "Restored history"}
            ]}
        ]}})
    elif method == "turn/start":
        text = params["input"][0]["text"]
        if text == "FAIL":
            emit({"id": message["id"], "error": {"code": -32000, "message": "Deliberate test error"}})
            continue
        turns += 1
        current = (params["threadId"], f"turn-{turns}")
        thread, turn = current
        event("turn/started", {"threadId": thread, "turn": {"id": turn}})
        if text == "HOLD":
            reply(message, {"turn": {"id": turn, "status": "inProgress"}})
            continue
        if text == "UNKNOWN":
            emit({"id": "unknown-1", "method": "unsupported/client/request", "params": {"threadId": thread, "turnId": turn}})
        for delta in ["Hello ", "λ", " from Codex"]:
            event("item/agentMessage/delta", {"threadId": thread, "turnId": turn, "itemId": "message-" + turn, "delta": delta})
        event("item/completed", {"threadId": thread, "turnId": turn, "item": {
            "type": "agentMessage", "id": "message-" + turn, "text": "Hello λ from Codex"
        }})
        complete()
        # Intentionally deliver completion before the turn/start response.
        reply(message, {"turn": {"id": turn, "status": "completed"}})
    elif method == "turn/interrupt":
        assert current == (params["threadId"], params["turnId"])
        reply(message, {})
        complete("interrupted")
    elif method == "never":
        pass
    elif method == "crash":
        os._exit(5)
    elif method is None:
        pass
    else:
        emit({"id": message["id"], "error": {"code": -32601, "message": "unknown test method"}})
