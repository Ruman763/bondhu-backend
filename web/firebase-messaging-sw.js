// Firebase Cloud Messaging service worker — required for web push.
// Must live at /firebase-messaging-sw.js (Flutter web serves from web/).
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBNc1yEPz_e54GSz4P8VM-PDua46IdGm38',
  appId: '1:870862996812:web:7d3958424c630e999abbe9',
  messagingSenderId: '870862996812',
  projectId: 'bondhu-a6497',
  storageBucket: 'bondhu-a6497.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  const title = payload.notification && payload.notification.title ? payload.notification.title : 'New message';
  const options = {
    body: payload.notification && payload.notification.body ? payload.notification.body : '',
    icon: '/icons/Icon-192.png',
    tag: payload.data && payload.data.chatId ? payload.data.chatId : 'bondhu-push',
    data: payload.data || {},
  };
  return self.registration.showNotification(title, options);
});
