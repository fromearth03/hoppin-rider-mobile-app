// FCM background service worker (NOTIF-01).
//
// GATED. This file is only meaningful once a real Firebase web-app config is
// pasted in below. With the placeholder values it fails to initialise and the
// worker is inert — which is CORRECT for the current build: delivery is gated
// on the backend FCM_CREDENTIALS_FILE (gaps 15/16) and on `device_os` accepting
// a web value (gap 69). It is registered explicitly (see web/index.html) so it
// never races Flutter's own service worker, and its registration failure is
// swallowed as a console.info — the app must boot regardless.
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

try {
  firebase.initializeApp({
    apiKey: 'FCM_API_KEY',
    authDomain: 'FCM_AUTH_DOMAIN',
    projectId: 'FCM_PROJECT_ID',
    messagingSenderId: 'FCM_SENDER_ID',
    appId: 'FCM_APP_ID',
  });

  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    const n = payload.notification || {};
    self.registration.showNotification(n.title || 'Hoppin', {
      body: n.body || '',
      icon: '/icons/Icon-192.png',
      // Carries the ASSUMED data payload { type, ride_id, deep_link } — gap 15.
      data: payload.data || {},
    });
  });
} catch (e) {
  // No real config compiled in. Expected today. Stay inert; never throw.
  console.info('[hoppin] FCM worker inert (GATED — no Firebase config):', e);
}

// Tap → open the app at the deep link the backend sent. The Dart tap-router
// ALLOWLISTS the target before it navigates (push_tap_router.dart) — this
// worker only opens the app; it does not get to choose the in-app route blind.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const target = typeof data.deep_link === 'string' ? data.deep_link : '/';
  event.waitUntil(clients.openWindow(target));
});
