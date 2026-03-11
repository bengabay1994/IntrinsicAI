import pytest
import requests

from src import eodhd_client, sec_edgar
from src.eodhd_client import EODHDDataClient


class DummyResponse:
    def __init__(self, status_code=200, text="", json_data=None):
        self.status_code = status_code
        self.text = text
        self._json_data = json_data or {}

    def json(self):
        return self._json_data


def test_eodhd_retries_transient_then_succeeds(monkeypatch):
    client = EODHDDataClient()

    class FakeApiClient:
        def __init__(self):
            self.calls = 0

        def get_fundamentals_data(self, ticker):
            self.calls += 1
            if self.calls < 3:
                raise RuntimeError("HTTP 503 Service Unavailable")
            return {"General": {"Code": ticker}}

    fake_api = FakeApiClient()
    client.client = fake_api

    sleep_calls = []
    monkeypatch.setattr(
        eodhd_client, "_backoff_sleep", lambda attempt: sleep_calls.append(attempt)
    )

    data = client.get_fundamentals("AAPL.US")

    assert data == {"General": {"Code": "AAPL.US"}}
    assert fake_api.calls == 3
    assert sleep_calls == [1, 2]


def test_eodhd_stops_immediately_on_permanent_error(monkeypatch):
    client = EODHDDataClient()

    class FakeApiClient:
        def __init__(self):
            self.calls = 0

        def get_fundamentals_data(self, _ticker):
            self.calls += 1
            raise RuntimeError("HTTP 404 Not Found")

    fake_api = FakeApiClient()
    client.client = fake_api

    sleep_calls = []
    monkeypatch.setattr(
        eodhd_client, "_backoff_sleep", lambda attempt: sleep_calls.append(attempt)
    )

    assert client.get_fundamentals("AAPL.US") is None
    assert fake_api.calls == 1
    assert sleep_calls == []


def test_sec_retries_transient_http_then_succeeds(monkeypatch):
    responses = [DummyResponse(status_code=503), DummyResponse(status_code=200)]

    def fake_get(*_args, **_kwargs):
        return responses.pop(0)

    sleep_calls = []
    monkeypatch.setattr(sec_edgar.requests, "get", fake_get)
    monkeypatch.setattr(
        sec_edgar, "_backoff_sleep", lambda attempt: sleep_calls.append(attempt)
    )
    monkeypatch.setattr(sec_edgar.time, "sleep", lambda _seconds: None)

    response = sec_edgar._make_request("https://example.com")

    assert response is not None
    assert response.status_code == 200
    assert sleep_calls == [1]


def test_sec_does_not_retry_permanent_http(monkeypatch):
    get_calls = []

    def fake_get(*_args, **_kwargs):
        get_calls.append(1)
        return DummyResponse(status_code=404)

    sleep_calls = []
    monkeypatch.setattr(sec_edgar.requests, "get", fake_get)
    monkeypatch.setattr(
        sec_edgar, "_backoff_sleep", lambda attempt: sleep_calls.append(attempt)
    )
    monkeypatch.setattr(sec_edgar.time, "sleep", lambda _seconds: None)

    response = sec_edgar._make_request("https://example.com")

    assert response is None
    assert len(get_calls) == 1
    assert sleep_calls == []


def test_sec_retries_request_exception_then_succeeds(monkeypatch):
    state = {"calls": 0}

    def fake_get(*_args, **_kwargs):
        state["calls"] += 1
        if state["calls"] < 3:
            raise requests.RequestException("connection reset")
        return DummyResponse(status_code=200)

    sleep_calls = []
    monkeypatch.setattr(sec_edgar.requests, "get", fake_get)
    monkeypatch.setattr(
        sec_edgar, "_backoff_sleep", lambda attempt: sleep_calls.append(attempt)
    )
    monkeypatch.setattr(sec_edgar.time, "sleep", lambda _seconds: None)

    response = sec_edgar._make_request("https://example.com")

    assert response is not None
    assert response.status_code == 200
    assert state["calls"] == 3
    assert sleep_calls == [1, 2]
