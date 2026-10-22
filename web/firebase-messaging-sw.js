importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDjYI2CH7yxAfo_Igu2oLpqU30Z__MBW_M',
  appId: '1:568304683655:web:b0e24bc1d8402701704622',
  messagingSenderId: '568304683655',
  projectId: 'pushkaapp-f4e4f',
  authDomain: 'pushkaapp-f4e4f.firebaseapp.com',
  storageBucket: 'pushkaapp-f4e4f.firebasestorage.app',
  measurementId: 'G-1R22009C3H'
});

firebase.messaging();
