import os
import time
import json
import logging
from eodhd import APIClient
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


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

        try:
            # The library likely returns a dictionary or JSON string
            # We wrap this to handle potential errors
            logger.info(f"Fetching fundamentals for {ticker}...")
            data = self.client.get_fundamentals_data(ticker)
            return data
        except Exception as e:
            logger.error(f"Error fetching data for {ticker}: {e}")
            return None

    def get_historical_data(
        self, ticker: str, period="d", from_date=None, to_date=None
    ):
        """
        Fetches historical price data.
        """
        if not self.client:
            raise ValueError("API Key not set.")

        try:
            data = self.client.get_eod_historical_stock_market_data(
                symbol=ticker, period=period, from_date=from_date, to_date=to_date
            )
            return data
        except Exception as e:
            logger.error(f"Error fetching historical data for {ticker}: {e}")
            return None


if __name__ == "__main__":
    # Test execution
    client = EODHDDataClient()
    print("Client initialized. Add a real key to .env to test.")
