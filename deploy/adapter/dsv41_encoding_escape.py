"""Escape literal image-placeholder text before DeepSeek-V4.1 prompt encoding.

Why this exists
---------------
`encoding_dsv41.encode_messages` (and the two validators it calls) reject any
model-bound message string that contains the literal image placeholder:

    400 "Message content contains image special token '...'. Images should be
         provided as image content blocks."

The official DeepSeek API instead renders such occurrences as plain text. A
client that legitimately *quotes* the token -- a tool result showing a model
source comment, a pasted error body, a code snippet -- therefore loses the whole
conversation: every retry replays the poisoned history and gets the same 400.

This adapter restores official-API parity: immediately before encoding, every
string in the outgoing ``messages`` / ``context`` graph is scanned and each
literal image-placeholder occurrence is rewritten to its ASCII form
``<|deepseek_image|>``, which the tokenizer treats as ordinary text. Genuine
image content blocks are untouched: the stock encoder still inserts its own
placeholder and reports the image through the media list, so multimodal
requests keep working exactly as before.

Failure policy: the caller (sitecustomize) wraps ``install`` and keeps the
stock encoder on any error, so a broken adapter degrades to the old 400
behavior (loudly, in the boot log) instead of breaking the server.

No env key is introduced on purpose: the fix is unconditional, adds no new
env surface (env-lint / GATE_FORM untouched), and is observable as one
``[encoding_escape]`` banner line after "banner complete".
"""

import functools

# ASCII bars only -- not a tokenizer special token, so it stays plain text.
_ESCAPED = '<|deepseek_image|>'

_PLACEHOLDER = None
_ARMED = False
_INSTALLED = False


def _scrub(value):
    """Return a copy of ``value`` with every literal image placeholder escaped."""
    if isinstance(value, str):
        return value.replace(_PLACEHOLDER, _ESCAPED)
    if isinstance(value, list):
        return [_scrub(item) for item in value]
    if isinstance(value, tuple):
        return tuple(_scrub(item) for item in value)
    if isinstance(value, dict):
        return {key: _scrub(item) for key, item in value.items()}
    return value


def _arm(module):
    global _PLACEHOLDER, _ARMED, _INSTALLED

    placeholder = getattr(module, 'IMAGE_PLACEHOLDER', None)
    if not isinstance(placeholder, str) or not placeholder:
        raise RuntimeError('encoding_dsv41.IMAGE_PLACEHOLDER missing/not a string')

    original = getattr(module, 'encode_messages', None)
    if not callable(original):
        raise RuntimeError('encoding_dsv41.encode_messages missing/not callable')

    @functools.wraps(original)
    def encode_messages(messages, *args, **kwargs):
        if _PLACEHOLDER is None:  # pragma: no cover - defensive
            return original(messages, *args, **kwargs)
        return original(_scrub(messages), *_scrub(args), **_scrub(kwargs))

    # Commit only after every check passed: a half-armed encoder must be
    # impossible.
    module._dsv41_encoding_escape_original = original
    module.encode_messages = encode_messages
    _PLACEHOLDER = placeholder
    _ARMED = True
    _INSTALLED = True


def install(module):
    """Patch one imported ``encoding_dsv41`` module. Idempotent.

    Returns True when armed, False when an earlier call refused.
    Raises on the first-call error so sitecustomize can report it.
    """
    if _INSTALLED:
        return _ARMED
    _arm(module)
    return _ARMED


def summary():
    """One-line state for the boot banner (no special-token literal on purpose)."""
    return 'armed=%d escape_ascii=%r surfaces=messages+context' % (
        int(_ARMED),
        _ESCAPED,
    )
