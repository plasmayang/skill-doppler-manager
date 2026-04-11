"""
Lease Monitor — background task to check lease expiry and emit notifications.
"""

import threading
import time
import logging
from typing import Callable, List, Optional

logger = logging.getLogger("lease_monitor")


class LeaseMonitor:
    """
    Background monitor that checks for expiring leases and emits notifications.
    """

    def __init__(
        self,
        check_interval: int = 30,
        warning_threshold: int = 60,
        callback: Optional[Callable] = None,
    ):
        """
        Args:
            check_interval: Seconds between lease checks
            warning_threshold: Seconds before expiry to emit warning
            callback: Function to call with notification dict
        """
        self.check_interval = check_interval
        self.warning_threshold = warning_threshold
        self.callback = callback
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._tracked_leases: List[dict] = []

    def track(self, secret: str, manager: str, expires_at: str):
        """Add a lease to track."""
        self._tracked_leases.append({
            "secret": secret,
            "manager": manager,
            "expires_at": expires_at,
        })

    def untrack(self, secret: str):
        """Remove a lease from tracking."""
        self._tracked_leases = [
            l for l in self._tracked_leases if l["secret"] != secret
        ]

    def start(self):
        """Start the background monitor."""
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        logger.info("Lease monitor started")

    def stop(self):
        """Stop the background monitor."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)
        logger.info("Lease monitor stopped")

    def _run(self):
        """Main loop."""
        while self._running:
            self._check_leases()
            time.sleep(self.check_interval)

    def _check_leases(self):
        """Check all tracked leases for expiry."""
        from datetime import datetime, timezone, timedelta

        now = datetime.now(timezone.utc)
        warning_cutoff = now + timedelta(seconds=self.warning_threshold)

        for lease in list(self._tracked_leases):
            try:
                expires = datetime.fromisoformat(lease["expires_at"].replace("Z", "+00:00"))
                if expires < now:
                    self._emit({
                        "type": "lease_expired",
                        "secret": lease["secret"],
                        "manager": lease["manager"],
                    })
                    self.untrack(lease["secret"])
                elif expires < warning_cutoff:
                    ttl = int((expires - now).total_seconds())
                    self._emit({
                        "type": "lease_expiring",
                        "secret": lease["secret"],
                        "manager": lease["manager"],
                        "ttl_seconds": ttl,
                    })
            except Exception as e:
                logger.error(f"Error checking lease {lease}: {e}")

    def _emit(self, notification: dict):
        """Emit a notification."""
        logger.info(f"Notification: {notification}")
        if self.callback:
            self.callback(notification)
