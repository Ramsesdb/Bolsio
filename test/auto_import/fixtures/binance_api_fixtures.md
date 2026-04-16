# Binance API Test Fixtures (Synthetic Data)

All values below are SYNTHETIC and do NOT represent real transactions or real API keys.

---

## C2C P2P — COMPLETED SELL (should parse as expense)

```json
{
  "orderNumber": "20250401001234567890",
  "tradeType": "SELL",
  "asset": "USDT",
  "fiat": "VES",
  "amount": "150.00",
  "totalPrice": "5625000.00",
  "unitPrice": "37500.00",
  "counterPartNickName": "Carlos_P2P",
  "createTime": 1711929600000,
  "orderStatus": "COMPLETED"
}
```

**Expected proposal:**
- amount: 150.0
- currencyId: "USD"
- type: expense
- counterpartyName: "Carlos_P2P"
- bankRef: "20250401001234567890"
- confidence: 0.95

---

## C2C P2P — COMPLETED BUY (should parse as income)

```json
{
  "orderNumber": "20250401009876543210",
  "tradeType": "BUY",
  "asset": "USDT",
  "fiat": "VES",
  "amount": "200.00",
  "totalPrice": "7500000.00",
  "unitPrice": "37500.00",
  "counterPartNickName": "Maria_VES",
  "createTime": 1711933200000,
  "orderStatus": "COMPLETED"
}
```

**Expected proposal:**
- amount: 200.0
- currencyId: "USD"
- type: income
- counterpartyName: "Maria_VES"
- bankRef: "20250401009876543210"
- confidence: 0.95

---

## C2C P2P — PENDING (should be IGNORED)

```json
{
  "orderNumber": "20250401005555555555",
  "tradeType": "BUY",
  "asset": "USDT",
  "fiat": "VES",
  "amount": "50.00",
  "totalPrice": "1875000.00",
  "unitPrice": "37500.00",
  "counterPartNickName": "Pending_User",
  "createTime": 1711936800000,
  "orderStatus": "PENDING"
}
```

**Expected:** `null` (ignored because status is not COMPLETED)

---

## Fiat Order — Successful Deposit

```json
{
  "orderNo": "FO20250402001122334455",
  "fiatCurrency": "USD",
  "indicatedAmount": "500.00",
  "amount": "500.00",
  "totalFee": "0.00",
  "method": "BPay VISA Card",
  "status": "Successful",
  "createTime": 1712001600000,
  "updateTime": 1712005200000
}
```

**Expected proposal:**
- amount: 500.0
- currencyId: "USD"
- type: income
- counterpartyName: "BPay VISA Card"
- bankRef: "FO20250402001122334455"
- confidence: 0.95

---

## Fiat Order — Failed (should be IGNORED)

```json
{
  "orderNo": "FO20250402009999999999",
  "fiatCurrency": "USD",
  "indicatedAmount": "100.00",
  "amount": "100.00",
  "totalFee": "0.00",
  "method": "Bank Transfer",
  "status": "Failed",
  "createTime": 1712008800000,
  "updateTime": 1712012400000
}
```

**Expected:** `null` (ignored because status is not Successful)

---

## Fiat Payment — Completed (card purchase of crypto)

```json
{
  "orderNo": "FP20250403001234",
  "sourceAmount": "100.00",
  "fiatCurrency": "USD",
  "obtainAmount": "99.50",
  "cryptoCurrency": "USDT",
  "totalFee": "0.50",
  "status": "Completed",
  "createTime": 1712088000000
}
```

**Expected proposal:**
- amount: 99.5
- currencyId: "USD"
- type: income
- counterpartyName: "Binance Card Purchase"
- bankRef: "FP20250403001234"
- confidence: 0.90

---

## Pay Transaction — SUCCESS

```json
{
  "orderType": "PAY",
  "transactionId": "PAY20250404001122",
  "amount": "25.00",
  "currency": "USDT",
  "transactionType": "PAY",
  "status": "SUCCESS",
  "counterparty": {
    "name": "Coffee Shop VE",
    "accountId": "123456",
    "binanceId": "BID789"
  },
  "createTime": 1712174400000
}
```

**Expected proposal:**
- amount: 25.0
- currencyId: "USD"
- type: expense
- counterpartyName: "Coffee Shop VE"
- bankRef: "PAY20250404001122"
- confidence: 0.90

---

## Capital Deposit — status=1 (confirmed), USDT

```json
{
  "id": "dep_001",
  "amount": "300.00",
  "coin": "USDT",
  "network": "TRX",
  "status": 1,
  "address": "TXyz1234567890abcdef1234567890abcd",
  "txId": "0xabc123def456789",
  "insertTime": 1712260800000
}
```

**Expected proposal:**
- amount: 300.0
- currencyId: "USD"
- type: income
- counterpartyName: "TXyz1234567890abcdef1234567890abcd"
- bankRef: "0xabc123def456789"
- confidence: 0.90

---

## Capital Deposit — status=1, BTC (non-stablecoin)

```json
{
  "id": "dep_002",
  "amount": "0.01500000",
  "coin": "BTC",
  "network": "BTC",
  "status": 1,
  "address": "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
  "txId": "0xbtc_hash_example",
  "insertTime": 1712264400000
}
```

**Expected proposal:**
- amount: 0.015
- currencyId: "BTC"
- type: income
- confidence: 0.60 (non-stablecoin)

---

## Capital Withdrawal — status=6 (completed)

```json
{
  "id": "wdr_001",
  "amount": "50.00",
  "coin": "USDT",
  "network": "TRX",
  "status": 6,
  "address": "TDestination1234567890abcdef12345",
  "txId": "0xwithdraw_hash_123",
  "applyTime": "2025-04-05 12:00:00"
}
```

**Expected proposal:**
- amount: 50.0
- currencyId: "USD"
- type: expense
- counterpartyName: "TDestination1234567890abcdef12345"
- bankRef: "wdr_001"
- confidence: 0.90
