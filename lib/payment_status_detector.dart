bool isFinalPaymentSignal(String value) {
  final text = value.toLowerCase();
  if (text.trim().isEmpty) {
    return false;
  }
  const successSignals = [
    'success',
    'successful',
    'succeeded',
    'paid',
    'approved',
    'completed',
    'confirmed',
    'оплата прошла',
    'оплачено',
    'успешно',
    'төлем өтті',
    'сәтті',
  ];
  const failureSignals = [
    'fail',
    'failed',
    'error',
    'declined',
    'cancel',
    'cancelled',
    'canceled',
    'expired',
    'rejected',
    'ошибка',
    'отклон',
    'отмен',
    'истек',
    'не прошла',
    'қате',
    'бас тарт',
    'мерзімі аяқ',
  ];
  return successSignals.any(text.contains) || failureSignals.any(text.contains);
}
