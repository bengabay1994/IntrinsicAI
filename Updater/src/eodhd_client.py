import os
import time
import json
import logging
import random
from eodhd import APIClient
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


MAX_RETRIES = 3
BASE_BACKOFF_SECONDS = 1.0
MAX_BACKOFF_SECONDS = 8.0
JITTER_SECONDS = 0.3

TRANSIENT_HTTP_STATUS_CODES = {408, 425, 429, 500, 502, 503, 504}
PERMANENT_HTTP_STATUS_CODES = {400, 401, 403, 404, 422}


def _extract_status_code(error: Exception) -> int | None:
    response = getattr(error, "response", None)
    if response is not None:
        status_code = getattr(response, "status_code", None)
        if isinstance(status_code, int):
            return status_code

    direct_status = getattr(error, "status_code", None)
    if isinstance(direct_status, int):
        return direct_status

    message = str(error)
    for token in message.replace(":", " ").split():
        if token.isdigit() and len(token) == 3:
            code = int(token)
            if 100 <= code <= 599:
                return code
    return None


def _is_transient_error(error: Exception) -> bool:
    status_code = _extract_status_code(error)
    if status_code is not None:
        if status_code in PERMANENT_HTTP_STATUS_CODES:
            return False
        return status_code in TRANSIENT_HTTP_STATUS_CODES or status_code >= 500

    transient_markers = [
        "timeout",
        "timed out",
        "temporarily unavailable",
        "connection reset",
        "connection aborted",
        "connection error",
        "network",
        "rate limit",
        "too many requests",
    ]
    message = str(error).lower()
    return any(marker in message for marker in transient_markers)


def _backoff_sleep(attempt: int) -> None:
    delay = min(MAX_BACKOFF_SECONDS, BASE_BACKOFF_SECONDS * (2 ** (attempt - 1)))
    jitter = random.uniform(0.0, JITTER_SECONDS)
    time.sleep(delay + jitter)


class EODHDDataClient:
    def __init__(self):
        self.api_key = os.getenv("EODHD_API_KEY")
        if not self.api_key or self.api_key == "YOUR_EODHD_API_KEY":
            logger.warning("EODHD_API_KEY is not set or is the default placeholder.")

        self.client = APIClient(self.api_key) if self.api_key else None

    def get_fundamentals(self, ticker: str):
        """
        Fetches fundamental data for a given ticker.
        """
        if not self.client:
            raise ValueError("API Key not set.")

        client = self.client
        logger.info(f"Fetching fundamentals for {ticker}...")
        return self._request_with_retry(
            operation="fundamentals",
            ticker=ticker,
            request_fn=lambda: client.get_fundamentals_data(ticker),
        )

    def get_historical_data(
        self, ticker: str, period="d", from_date=None, to_date=None
    ):
        """
        Fetches historical price data.
        """
        if not self.client:
            raise ValueError("API Key not set.")

        client = self.client
        return self._request_with_retry(
            operation="historical data",
            ticker=ticker,
            request_fn=lambda: client.get_eod_historical_stock_market_data(
                symbol=ticker, period=period, from_date=from_date, to_date=to_date
            ),
        )

    def _request_with_retry(self, operation: str, ticker: str, request_fn):
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                return request_fn()
            except Exception as error:
                is_transient = _is_transient_error(error)
                status_code = _extract_status_code(error)
                status_label = f" status={status_code}" if status_code else ""

                if not is_transient:
                    logger.error(
                        f"Permanent EODHD error while fetching {operation} for {ticker}:{status_label} {error}"
                    )
                    return None

                if attempt == MAX_RETRIES:
                    logger.error(
                        f"Transient EODHD error persisted after {MAX_RETRIES} attempts for {operation} {ticker}:{status_label} {error}"
                    )
                    return None

                logger.warning(
                    f"Transient EODHD error on attempt {attempt}/{MAX_RETRIES} for {operation} {ticker}:{status_label} {error}. Retrying with backoff."
                )
                _backoff_sleep(attempt)

        return None


if __name__ == "__main__":
    # Test execution
    client = EODHDDataClient()
    print("Client initialized. Add a real key to .env to test.")
