"""CEO Letters orchestrator: fetches 10-K filings, extracts CEO letters, summarizes with Gemini."""

import os
import sqlite3
from datetime import datetime, timezone

from dotenv import load_dotenv
from google import genai

from .sec_edgar import resolve_cik, get_10k_filings, download_filing_text

# Load environment variables
load_dotenv()

# Gemini model for summarization
GEMINI_MODEL = "gemini-2.5-flash"

# Number of years of CEO letters to fetch
DEFAULT_LETTER_COUNT = 5

# System prompt for Gemini summarization
SUMMARIZATION_PROMPT = """You are an expert at analyzing CEO and Chairman letters to shareholders \
from annual reports (10-K filings). Your analysis focuses on Rule #1 value investing criteria.

From the following excerpt of a company's annual report (10-K filing), extract and summarize the \
CEO's or Chairman's letter to shareholders.

Focus your summary on these aspects relevant to Rule #1 value investing:

1. **Management Quality & Integrity** - Does the CEO communicate honestly about challenges? \
Do they take responsibility for failures or make excuses? Are they transparent about risks?

2. **Competitive Moat Discussion** - Does the CEO mention brand strength, switching costs, \
network effects, toll-bridge economics, or other durable competitive advantages?

3. **Capital Allocation Strategy** - How is management deploying cash? Share buybacks, dividends, \
debt reduction, acquisitions, or reinvestment? Is it owner-oriented or empire-building?

4. **Business Outlook & Risks** - What does leadership see ahead? Are they realistic about \
challenges or blindly optimistic? Do they acknowledge competitive threats?

5. **Growth Signals** - Any mention of expanding margins, entering new markets, pricing power, \
or sustainable revenue growth drivers?

6. **Red Flags** - Excessive executive compensation discussion, blame-shifting, vague strategy, \
aggressive accounting language, or signs of dishonesty.

Rules:
- Keep the summary to 300-500 words, focused and actionable for an investor.
- Use bullet points within each section for clarity.
- If no CEO/Chairman letter is found in the text, respond with exactly: NO_LETTER_FOUND
- Do not fabricate information. Only summarize what is actually in the text.
- Quote specific phrases from the letter when they reveal management character."""


def _get_gemini_client() -> genai.Client | None:
    """Creates a Gemini API client using the API key from environment."""
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key or api_key == "your_gemini_api_key_here":
        print("  [CEO Letters] GEMINI_API_KEY not set. Skipping summarization.")
        print("  [CEO Letters] Get a free key at: https://aistudio.google.com/apikey")
        return None

    try:
        client = genai.Client(api_key=api_key)
        return client
    except Exception as e:
        print(f"  [CEO Letters] Error creating Gemini client: {e}")
        return None


def _summarize_with_gemini(
    client: genai.Client,
    text: str,
    ticker: str,
    fiscal_year: int,
) -> str | None:
    """
    Uses Gemini Flash 2.5 to extract and summarize the CEO letter from filing text.

    Args:
        client: Gemini API client.
        text: Extracted text excerpt from the 10-K filing.
        ticker: Stock ticker (for context in the prompt).
        fiscal_year: Fiscal year of the filing.

    Returns:
        Summary string, or None on failure.
    """
    clean_ticker = ticker.split(".")[0].upper()
    user_prompt = (
        f"Company: {clean_ticker} | Fiscal Year: {fiscal_year}\n\n"
        f"--- BEGIN 10-K EXCERPT ---\n{text}\n--- END 10-K EXCERPT ---"
    )

    try:
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=user_prompt,
            config=genai.types.GenerateContentConfig(
                system_instruction=SUMMARIZATION_PROMPT,
                temperature=0.3,
                max_output_tokens=2048,
            ),
        )
        summary = response.text
        if summary and summary.strip():
            return summary.strip()
        return None

    except Exception as e:
        print(f"  [CEO Letters] Gemini API error: {e}")
        return None


def _get_cached_years(ticker: str, conn: sqlite3.Connection) -> set[int]:
    """Returns the set of fiscal years we already have CEO letters cached for."""
    cursor = conn.cursor()
    cursor.execute(
        "SELECT fiscal_year FROM ceo_letters WHERE ticker = ?",
        (ticker,),
    )
    return {row[0] for row in cursor.fetchall()}


def _save_letter(
    conn: sqlite3.Connection,
    ticker: str,
    fiscal_year: int,
    filing_date: str,
    raw_excerpt: str | None,
    summary: str | None,
) -> None:
    """Upserts a CEO letter into the database."""
    cursor = conn.cursor()
    cursor.execute(
        """
        INSERT INTO ceo_letters (ticker, fiscal_year, filing_date, raw_excerpt, summary, fetched_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(ticker, fiscal_year) DO UPDATE SET
            filing_date = excluded.filing_date,
            raw_excerpt = excluded.raw_excerpt,
            summary = excluded.summary,
            fetched_at = excluded.fetched_at
        """,
        (
            ticker,
            fiscal_year,
            filing_date,
            raw_excerpt,
            summary,
            datetime.now(timezone.utc).isoformat(),
        ),
    )
    conn.commit()


def fetch_ceo_letters(
    ticker: str,
    conn: sqlite3.Connection,
    count: int = DEFAULT_LETTER_COUNT,
    force: bool = False,
) -> None:
    """
    Fetches and summarizes CEO letters to shareholders for a ticker.

    Pipeline:
      1. Resolve ticker to CIK (SEC identifier)
      2. Get last N 10-K filings from EDGAR
      3. For each filing not already cached:
         a. Download the filing HTML
         b. Extract text before "Item 1" (where CEO letters live)
         c. Send to Gemini Flash 2.5 for summarization
         d. Store in ceo_letters table

    Args:
        ticker: Stock ticker (e.g., "AAPL" or "AAPL.US").
        conn: SQLite database connection.
        count: Number of years of letters to fetch (default 5).
        force: If True, re-fetch even if already cached.
    """
    clean_ticker = ticker.split(".")[0].upper()
    print(f"\n[CEO Letters] Processing {clean_ticker}...")

    # Step 1: Resolve ticker to CIK
    print(f"  [CEO Letters] Resolving CIK for {clean_ticker}...")
    cik = resolve_cik(clean_ticker)
    if cik is None:
        print(f"  [CEO Letters] Could not resolve CIK for {clean_ticker}. Skipping.")
        return

    print(f"  [CEO Letters] CIK: {cik}")

    # Step 2: Get 10-K filings
    print(f"  [CEO Letters] Fetching 10-K filings...")
    filings = get_10k_filings(cik, count=count)
    if not filings:
        print(f"  [CEO Letters] No 10-K filings found for {clean_ticker}. Skipping.")
        return

    print(f"  [CEO Letters] Found {len(filings)} 10-K filings")

    # Check what we already have cached
    cached_years = _get_cached_years(ticker, conn)
    if not force and cached_years:
        print(f"  [CEO Letters] Already cached years: {sorted(cached_years)}")

    # Step 3: Initialize Gemini client
    gemini_client = _get_gemini_client()
    if gemini_client is None:
        print(
            f"  [CEO Letters] No Gemini client. Will save raw excerpts without summaries."
        )

    # Step 4: Process each filing
    for filing in filings:
        fiscal_year = filing.fiscal_year
        if fiscal_year is None:
            print(
                f"  [CEO Letters] Skipping filing with unknown fiscal year: {filing.filing_date}"
            )
            continue

        if not force and fiscal_year in cached_years:
            print(f"  [CEO Letters] FY{fiscal_year} already cached. Skipping.")
            continue

        print(
            f"  [CEO Letters] Processing FY{fiscal_year} (filed {filing.filing_date})..."
        )

        # Download and extract text
        raw_excerpt = download_filing_text(filing)
        if raw_excerpt is None:
            print(
                f"  [CEO Letters] Could not extract text for FY{fiscal_year}. Skipping."
            )
            continue

        word_count = len(raw_excerpt.split())
        print(f"  [CEO Letters] Extracted {word_count} words from 10-K")

        # Summarize with Gemini
        summary = None
        if gemini_client is not None:
            print(f"  [CEO Letters] Summarizing with Gemini ({GEMINI_MODEL})...")
            summary = _summarize_with_gemini(
                gemini_client,
                raw_excerpt,
                clean_ticker,
                fiscal_year,
            )

            if summary and summary.strip() == "NO_LETTER_FOUND":
                print(f"  [CEO Letters] No CEO letter found in FY{fiscal_year} 10-K")
                summary = None
            elif summary:
                print(f"  [CEO Letters] Summary generated ({len(summary)} chars)")
            else:
                print(f"  [CEO Letters] Summarization failed for FY{fiscal_year}")

        # Save to database
        _save_letter(
            conn=conn,
            ticker=ticker,
            fiscal_year=fiscal_year,
            filing_date=filing.filing_date,
            raw_excerpt=raw_excerpt,
            summary=summary,
        )
        print(f"  [CEO Letters] Saved FY{fiscal_year} to database")

    print(f"[CEO Letters] Done processing {clean_ticker}")


def run_ceo_letters(
    tickers: list[str], count: int = DEFAULT_LETTER_COUNT, force: bool = False
) -> None:
    """
    Fetches CEO letters for a list of tickers.

    Args:
        tickers: List of stock tickers.
        count: Number of years per ticker.
        force: If True, re-fetch even if cached.
    """
    from .db import get_db_connection, initialize_db

    initialize_db()
    conn = get_db_connection()

    try:
        for ticker in tickers:
            fetch_ceo_letters(ticker, conn, count=count, force=force)
    finally:
        conn.close()

    print(f"\n[CEO Letters] Completed processing {len(tickers)} ticker(s)")
