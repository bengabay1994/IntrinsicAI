"""SEC EDGAR API client for fetching 10-K filings and extracting CEO letters."""

import re
import time
import random
import logging
from dataclasses import dataclass

import requests
from bs4 import BeautifulSoup


# SEC requires a descriptive User-Agent with contact email.
USER_AGENT = "IntrinsicAI/1.0 bengabay1994@gmail.com"

# Rate limit: SEC asks for max 10 req/sec. We use 1 req/sec to be safe.
REQUEST_DELAY_SECONDS = 1.0

# Maximum words to extract from the beginning of the 10-K (before Item 1).
MAX_EXCERPT_WORDS = 5000

MAX_RETRIES = 3
BASE_BACKOFF_SECONDS = 1.0
MAX_BACKOFF_SECONDS = 8.0
JITTER_SECONDS = 0.3

TRANSIENT_HTTP_STATUS_CODES = {408, 425, 429, 500, 502, 503, 504}
PERMANENT_HTTP_STATUS_CODES = {400, 401, 403, 404, 422}

logger = logging.getLogger(__name__)


def _is_transient_http_error(status_code: int) -> bool:
    if status_code in PERMANENT_HTTP_STATUS_CODES:
        return False
    return status_code in TRANSIENT_HTTP_STATUS_CODES or status_code >= 500


def _backoff_sleep(attempt: int) -> None:
    delay = min(MAX_BACKOFF_SECONDS, BASE_BACKOFF_SECONDS * (2 ** (attempt - 1)))
    jitter = random.uniform(0.0, JITTER_SECONDS)
    time.sleep(delay + jitter)


@dataclass
class SecFiling:
    """Represents a single SEC 10-K filing."""

    accession_number: str
    filing_date: str
    report_date: str
    primary_document: str
    cik: str
    fiscal_year: int | None = None

    @property
    def document_url(self) -> str:
        """Constructs the full URL to the primary filing document."""
        cik_clean = self.cik.lstrip("0")
        accession_clean = self.accession_number.replace("-", "")
        return (
            f"https://www.sec.gov/Archives/edgar/data/"
            f"{cik_clean}/{accession_clean}/{self.primary_document}"
        )


def _make_request(
    url: str, accept: str = "application/json"
) -> requests.Response | None:
    """Makes an HTTP request to SEC EDGAR with proper headers and rate limiting."""
    headers = {
        "User-Agent": USER_AGENT,
        "Accept-Encoding": "gzip, deflate",
        "Accept": accept,
    }

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = requests.get(url, headers=headers, timeout=30)
            time.sleep(REQUEST_DELAY_SECONDS)

            if response.status_code == 200:
                return response

            is_transient = _is_transient_http_error(response.status_code)
            if not is_transient:
                logger.error(
                    "[SEC EDGAR] Permanent HTTP %s for %s",
                    response.status_code,
                    url,
                )
                return None

            if attempt == MAX_RETRIES:
                logger.error(
                    "[SEC EDGAR] Transient HTTP %s persisted after %s attempts for %s",
                    response.status_code,
                    MAX_RETRIES,
                    url,
                )
                return None

            logger.warning(
                "[SEC EDGAR] Transient HTTP %s on attempt %s/%s for %s. Retrying with backoff.",
                response.status_code,
                attempt,
                MAX_RETRIES,
                url,
            )
            _backoff_sleep(attempt)

        except requests.RequestException as error:
            if attempt == MAX_RETRIES:
                logger.error(
                    "[SEC EDGAR] Request error persisted after %s attempts for %s: %s",
                    MAX_RETRIES,
                    url,
                    error,
                )
                return None

            logger.warning(
                "[SEC EDGAR] Request error on attempt %s/%s for %s: %s. Retrying with backoff.",
                attempt,
                MAX_RETRIES,
                url,
                error,
            )
            _backoff_sleep(attempt)

    return None


def resolve_cik(ticker: str) -> str | None:
    """
    Resolves a stock ticker to its SEC CIK number.

    Uses the SEC company tickers JSON endpoint to find the mapping.
    The ticker should be the base symbol (e.g., "AAPL" not "AAPL.US").

    Args:
        ticker: Stock ticker symbol (e.g., "AAPL").

    Returns:
        Zero-padded CIK string (e.g., "0000320193") or None if not found.
    """
    # Clean the ticker: remove exchange suffix if present (e.g., "AAPL.US" -> "AAPL")
    clean_ticker = ticker.split(".")[0].upper()

    url = "https://www.sec.gov/files/company_tickers.json"
    response = _make_request(url)
    if response is None:
        return None

    try:
        data = response.json()
        for entry in data.values():
            if entry.get("ticker", "").upper() == clean_ticker:
                cik = str(entry["cik_str"])
                # Zero-pad to 10 digits
                return cik.zfill(10)
    except (ValueError, KeyError) as e:
        logger.error("[SEC EDGAR] Error parsing tickers JSON: %s", e)

    logger.warning("[SEC EDGAR] CIK not found for ticker: %s", clean_ticker)
    return None


def get_10k_filings(cik: str, count: int = 5) -> list[SecFiling]:
    """
    Fetches the most recent 10-K filings for a company from SEC EDGAR.

    Args:
        cik: Zero-padded CIK number (e.g., "0000320193").
        count: Maximum number of 10-K filings to return.

    Returns:
        List of SecFiling objects, most recent first.
    """
    url = f"https://data.sec.gov/submissions/CIK{cik}.json"
    response = _make_request(url)
    if response is None:
        return []

    try:
        data = response.json()
        recent = data.get("filings", {}).get("recent", {})

        forms = recent.get("form", [])
        accession_numbers = recent.get("accessionNumber", [])
        filing_dates = recent.get("filingDate", [])
        report_dates = recent.get("reportDate", [])
        primary_docs = recent.get("primaryDocument", [])

        filings: list[SecFiling] = []
        for i in range(len(forms)):
            if forms[i] == "10-K" and len(filings) < count:
                # Extract fiscal year from report date
                fiscal_year = None
                if i < len(report_dates) and report_dates[i]:
                    try:
                        fiscal_year = int(report_dates[i][:4])
                    except (ValueError, IndexError):
                        pass

                filing = SecFiling(
                    accession_number=accession_numbers[i],
                    filing_date=filing_dates[i] if i < len(filing_dates) else "",
                    report_date=report_dates[i] if i < len(report_dates) else "",
                    primary_document=primary_docs[i] if i < len(primary_docs) else "",
                    cik=cik,
                    fiscal_year=fiscal_year,
                )
                filings.append(filing)

        return filings

    except (ValueError, KeyError) as e:
        logger.error("[SEC EDGAR] Error parsing submissions: %s", e)
        return []


def download_filing_text(filing: SecFiling) -> str | None:
    """
    Downloads a 10-K filing and extracts the text before "Item 1" / "PART I".

    This is where CEO letters to shareholders typically live in 10-K filings.

    Args:
        filing: SecFiling object with the document URL.

    Returns:
        Extracted text excerpt (up to MAX_EXCERPT_WORDS words) or None on failure.
    """
    url = filing.document_url
    logger.info("[SEC EDGAR] Downloading: %s", url)

    response = _make_request(url, accept="text/html")
    if response is None:
        return None

    try:
        html_content = response.text

        # Parse HTML and extract text
        soup = BeautifulSoup(html_content, "html.parser")

        # Remove script and style elements
        for element in soup(["script", "style"]):
            element.decompose()

        full_text = soup.get_text(separator="\n")

        # Clean up whitespace
        lines = [line.strip() for line in full_text.splitlines()]
        text = "\n".join(line for line in lines if line)

        # Extract text before "Item 1" or "PART I" (case-insensitive)
        # CEO letters are typically in the front matter before formal sections.
        excerpt = _extract_before_item1(text)

        if not excerpt or len(excerpt.split()) < 50:
            # If extraction failed or text is too short, try taking the first
            # MAX_EXCERPT_WORDS words of the full document
            words = text.split()
            excerpt = " ".join(words[:MAX_EXCERPT_WORDS])

        # Truncate to MAX_EXCERPT_WORDS
        words = excerpt.split()
        if len(words) > MAX_EXCERPT_WORDS:
            excerpt = " ".join(words[:MAX_EXCERPT_WORDS])

        return excerpt if excerpt.strip() else None

    except Exception as e:
        logger.error("[SEC EDGAR] Error extracting text from %s: %s", url, e)
        return None


def _extract_before_item1(text: str) -> str:
    """
    Extracts text from the beginning of a 10-K up to the first "Item 1" heading.

    The CEO letter typically appears before the formal 10-K sections. We look for
    common markers that indicate the start of the structured 10-K content.

    Args:
        text: Full plain text of the 10-K filing.

    Returns:
        Text before the first structural marker, or empty string if not found.
    """
    # Patterns that mark the start of formal 10-K content
    # We want everything BEFORE these markers
    patterns = [
        # "PART I" standalone on a line or "PART I" as a heading
        r"(?m)^[\s]*PART\s+I[\s]*$",
        r"(?m)^[\s]*PART\s+I\b[^IV]",
        # "Item 1." or "Item 1 " (the first formal item)
        r"(?mi)^[\s]*Item\s+1[\.\s]",
        # "ITEM 1." or "ITEM 1 "
        r"(?m)^[\s]*ITEM\s+1[\.\s]",
        # Table of contents often precedes the letter
        r"(?mi)TABLE\s+OF\s+CONTENTS",
    ]

    earliest_pos = len(text)
    for pattern in patterns:
        match = re.search(pattern, text)
        if match and match.start() < earliest_pos:
            # Only use if there's meaningful content before it (>100 chars)
            if match.start() > 100:
                earliest_pos = match.start()

    if earliest_pos < len(text):
        return text[:earliest_pos].strip()

    return ""
