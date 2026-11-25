<%@ page trimDirectiveWhitespaces="true" contentType="application/json;charset=UTF-8" %><%@ include file="/WEB-INF/jspf/common.jspf" %><%@ include file="/WEB-INF/jspf/security.jspf" %><%@ include file="/WEB-INF/jspf/db.jspf" %><%@ include file="/WEB-INF/jspf/gateways.jspf" %><%@ include file="/WEB-INF/jspf/callback.jspf" %><%
  applySecurityHeaders(response, false);

  if (!isAllowedIp(request, "PAYMENT_WEBHOOK_ALLOWED_IPS")) {
    response.setStatus(HttpServletResponse.SC_NOT_FOUND);
    out.print(GSON.toJson(Map.of("success", false, "code", "ROUTE_NOT_FOUND", "message", "Route not found")));
    return;
  }

  if (!checkRateLimit(application, response, "webhook", clientIp(request), 300)) {
    return;
  }

  if (!"POST".equalsIgnoreCase(request.getMethod())) {
    response.setStatus(HttpServletResponse.SC_METHOD_NOT_ALLOWED);
    out.print(GSON.toJson(Map.of("success", false, "code", "METHOD_NOT_ALLOWED")));
    return;
  }

  String pathInfo = request.getPathInfo();
  String provider = (pathInfo != null && pathInfo.startsWith("/")) ? pathInfo.substring(1).split("/")[0].trim().toLowerCase() : "";
  if (provider.isEmpty() || !provider.matches("^[a-z0-9_-]{1,32}$") || (isProductionEnv() && "mock".equals(provider))) {
    response.setStatus(HttpServletResponse.SC_NOT_FOUND);
    out.print(GSON.toJson(Map.of("success", false, "code", "UNKNOWN_PROVIDER")));
    return;
  }

  byte[] rawBody = readBodyCapped(request, MAX_WEBHOOK_BODY_BYTES);
  if (rawBody == null) {
    response.setStatus(413);
    out.print(GSON.toJson(Map.of("success", false, "code", "PAYLOAD_TOO_LARGE", "message", "Webhook payload too large")));
    return;
  }

  Map<String, Object> parsed = parseAndVerifyGatewayWebhook(provider, request, rawBody);
  if (!Boolean.TRUE.equals(parsed.get("ok"))) {
    response.setStatus(((Number) parsed.get("httpStatus")).intValue());
    out.print(GSON.toJson(Map.of("success", false, "code", parsed.get("code"), "message", parsed.get("message"))));
    return;
  }

  String paymentOrderId = String.valueOf(parsed.get("paymentOrderId"));
  String providerOrderId = String.valueOf(parsed.get("providerOrderId"));
  String normalizedStatus = String.valueOf(parsed.get("normalizedStatus"));

  Map<String, Object> order = !paymentOrderId.isEmpty()
      ? repoFindOrderById(application, paymentOrderId)
      : repoFindOrderByProviderId(application, providerOrderId);
  if (order == null) {
    response.setStatus(HttpServletResponse.SC_NOT_FOUND);
    out.print(GSON.toJson(Map.of("success", false, "code", "ORDER_NOT_FOUND")));
    return;
  }

  String resolvedOrderId = String.valueOf(order.get("paymentOrderId"));
  String headerEventId = request.getHeader("X-Razorpay-Event-Id");
  String providerEventId = (headerEventId != null && !headerEventId.trim().isEmpty())
      ? headerEventId.trim()
      : ("sha256:" + sha256Hex(rawBody));

  boolean fresh = repoRecordWebhookAndUpdate(application, providerEventId, provider, resolvedOrderId, normalizedStatus);
  if (!fresh) {
    response.setStatus(HttpServletResponse.SC_OK);
    out.print(GSON.toJson(Map.of("success", true, "duplicate", true, "paymentOrderId", resolvedOrderId)));
    return;
  }

  order.put("status", normalizedStatus);
  int nodeStatus = sendNodePaymentEvent(application, order, normalizedStatus);

  response.setStatus(HttpServletResponse.SC_OK);
  out.print(GSON.toJson(Map.of(
      "success", true,
      "provider", provider,
      "paymentOrderId", resolvedOrderId,
      "providerOrderId", order.get("providerOrderId"),
      "status", normalizedStatus,
      "nodeCallbackStatus", nodeStatus
  )));
%>
