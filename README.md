# AAITripJavaBase (Pure JSP — Zero `.java` Files, Zero Frameworks)

Transactional payments service built purely with **JSP + `.jspf` + `web.xml`**, implementing `AAITripBackendBase/docs/payments-contract.md` with pluggable gateway support (Razorpay included).

## Endpoints (Mapped in `WEB-INF/web.xml`)
- `POST /internal/payments/orders` → `/WEB-INF/jsp/orders.jsp` (Bearer `JAVA_SERVICE_TOKEN` + 24h `Idempotency-Key`)
- `GET /internal/payments/orders/{paymentOrderId}` → `/WEB-INF/jsp/orders.jsp`
- `POST /api/payments/v1/webhooks/{provider}` → `/WEB-INF/jsp/webhook.jsp` (e.g. `/api/payments/v1/webhooks/razorpay` verifies `X-Razorpay-Signature`, updates order, sends signed callback to Node `POST /internal/v1/payments/events`)
- `GET /` or `GET /dashboard` → `/WEB-INF/jsp/dashboard.jsp`
- `GET /health` → `/WEB-INF/jsp/health.jsp`

## Adding Another Payment Gateway Later
1. Open `src/main/webapp/WEB-INF/jspf/gateways.jspf`.
2. Add your gateway block in `createGatewayOrder(...)` and `parseAndVerifyGatewayWebhook(...)`.
3. Set `PAYMENT_GATEWAY=<provider>` in environment variables.

## Run Locally (Embedded Jetty 12 on port 8082)
```bash
export PAYMENT_GATEWAY=razorpay
export RAZORPAY_KEY_ID="rzp_test_xxx"
export RAZORPAY_KEY_SECRET="xxx"
export RAZORPAY_WEBHOOK_SECRET="xxx"
export JAVA_SERVICE_TOKEN="dev-java-service-token-at-least-32-chars"
export JAVA_CALLBACK_SECRET="your-32-char-callback-secret-matching-node"
export NODE_CALLBACK_URL="http://127.0.0.1:4101/internal/v1/payments/events"
mvn jetty:run
```
(If `RAZORPAY_KEY_ID` is unset in development, `PAYMENT_GATEWAY` automatically defaults to `mock`.)

## Deploy to Apache Tomcat 10.1+ / 11
```bash
mvn clean package
# Copy target/aaitrip-java-payments.war to Tomcat webapps/
```
