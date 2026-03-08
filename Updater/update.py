import sys
from src.ingest import run_updater
from src.ceo_letters import run_ceo_letters
import argparse


def main():
    parser = argparse.ArgumentParser(description="IntrinsicAI Data Updater")
    parser.add_argument(
        "--mode", choices=["bulk", "daily"], default="daily", help="Update mode"
    )
    parser.add_argument("--tickers", nargs="+", help="List of tickers")
    parser.add_argument("--local", help="Path to local JSON file to ingest")

    # CEO Letters options
    parser.add_argument(
        "--letters",
        action="store_true",
        help="Fetch CEO annual letters to shareholders from SEC 10-K filings",
    )
    parser.add_argument(
        "--skip-financials",
        action="store_true",
        help="Skip financial data update (use with --letters to only fetch letters)",
    )
    parser.add_argument(
        "--letter-years",
        type=int,
        default=5,
        help="Number of years of CEO letters to fetch (default: 5)",
    )
    parser.add_argument(
        "--force-letters",
        action="store_true",
        help="Re-fetch CEO letters even if already cached",
    )

    args = parser.parse_args()

    # Default tickers if none provided
    tickers = (
        args.tickers if args.tickers else ["AAPL", "MSFT", "GOOGL", "AMZN", "META"]
    )

    # Run financial data update (unless skipped)
    if not args.skip_financials:
        if args.local:
            run_updater(args.mode, [], local_file=args.local)
        else:
            run_updater(args.mode, tickers)

    # Run CEO letters fetch (if requested)
    if args.letters:
        run_ceo_letters(
            tickers,
            count=args.letter_years,
            force=args.force_letters,
        )


if __name__ == "__main__":
    main()
