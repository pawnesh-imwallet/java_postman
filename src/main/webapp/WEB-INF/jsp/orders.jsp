<%@ page trimDirectiveWhitespaces="true" contentType="application/json;charset=UTF-8" %><%@ include file="/WEB-INF/jspf/common.jspf" %><%@ include file="/WEB-INF/jspf/security.jspf" %><%@ include file="/WEB-INF/jspf/db.jspf" %><%@ include file="/WEB-INF/jspf/gateways.jspf" %><%
  applySecurityHeaders(response, false);

  if (!isAllowedIp(request, "NODE_ALLOWED_IPS")) {
    response.setStatus(HttpServletResponse.SC_NOT_FOUND);
    out.print(GSON.toJson(Map.of("success", false, "code", "ROUTE_NOT_FOUND", "message", "Route not found")));
    return;
  }

  if (!checkRateLimit(application, response, "internal", clientIp(request), 300)) {
    return;
  }

  if (!authenticateInternalRequest(request, response)) {
    return;
  }

  String method = request.getMethod().toUpperCase();
  String pathInfo = request.getPathInfo();

  if ("GET".equals(method)) {
    String id = (pathInfo != null && pathInfo.startsWith("/")) ? pathInfo.substring(1).trim() : "";
    if (!REF_ID.matcher(id).matches()) {
      response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
      out.print(GSON.toJson(Map.of("error", "Invalid paymentOrderId")));
      return;
    }
    Map<String, Object> order = repoFindOrderById(application, id);
    if (order == null) {
      response.setStatus(HttpServletResponse.SC_NOT_FOUND);
      out.print(GSON.toJson(Map.of("error", "Payment order not found")));
      return;
    }
    Map<String, Object> dto = new LinkedHashMap<String, Object>();
    dto.put("paymentOrderId", order.get("paymentOrderId"));
    dto.put("providerOrderId", order.get("providerOrderId"));
    dto.put("status", order.get("status"));
    dto.put("amountMinor", order.get("amountMinor"));
    dto.put("currency", order.get("currency"));
    response.setStatus(HttpServletResponse.SC_OK);
    out.print(GSON.toJson(dto));
    return;
  }

  if (!"POST".equals(method)) {
    response.setStatus(HttpServletResponse.SC_METHOD_NOT_ALLOWED);
    out.print(GSON.toJson(Map.of("error", "Method not allowed")));
    return;
  }

  if (pathInfo != null && !pathInfo.equals("/")) {
    response.setStatus(HttpServletResponse.SC_NOT_FOUND);
    out.print(GSON.toJson(Map.of("error", "Route not found")));
    return;
  }

  String idempotencyKey = request.getHeader("Idempotency-Key");
  if (idempotencyKey == null || !REF_ID.matcher(idempotencyKey.trim()).matches()) {
    response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
    out.print(GSON.toJson(Map.of("error", "Valid Idempotency-Key header is required")));
    return;
  }
  idempotencyKey = idempotencyKey.trim();

  byte[] raw = readBodyCapped(request, MAX_ORDER_BODY_BYTES);
  if (raw == null) {
    response.setStatus(413);
    out.print(GSON.toJson(Map.of("error", "Payload too large", "code", "PAYLOAD_TOO_LARGE")));
    return;
  }

  JsonObject body;
  try {
    JsonElement el = JsonParser.parseString(new String(raw, StandardCharsets.UTF_8));
    if (!el.isJsonObject() || isUnsafeJson(el, 0)) {
      response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
      out.print(GSON.toJson(Map.of("error", "Request contains unsupported data", "code", "INVALID_BODY")));
      return;
    }
    body = el.getAsJsonObject();
  } catch (Exception e) {
    response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
    out.print(GSON.toJson(Map.of("error", "Invalid JSON body")));
    return;
  }

  String bookingId = (body.has("bookingId") && !body.get("bookingId").isJsonNull()) ? body.get("bookingId").getAsString().trim() : null;
  String userId = (body.has("userId") && !body.get("userId").isJsonNull()) ? body.get("userId").getAsString().trim() : null;
  String currency = (body.has("currency") && !body.get("currency").isJsonNull()) ? body.get("currency").getAsString().trim() : null;

  long amountMinor;
  try {
    if (!body.has("amountMinor") || !body.get("amountMinor").getAsJsonPrimitive().isNumber()) {
      throw new IllegalArgumentException();
    }
    double d = body.get("amountMinor").getAsDouble();
    amountMinor = body.get("amountMinor").getAsLong();
    if (d != amountMinor || amountMinor < 100 || amountMinor > MAX_AMOUNT_MINOR) throw new IllegalArgumentException();
  } catch (Exception e) {
    response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
    out.print(GSON.toJson(Map.of("error", "amountMinor must be an integer between 100 and " + MAX_AMOUNT_MINOR + " paise")));
    return;
  }

  if (bookingId == null || !REF_ID.matcher(bookingId).matches()
      || userId == null || userId.isEmpty() || userId.length() > 64 || !REF_ID.matcher(userId).matches()
      || !"INR".equals(currency)) {
    response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
    out.print(GSON.toJson(Map.of("error", "Invalid bookingId, userId, or currency")));
    return;
  }

  String provider = activeGatewayName();
  if (isProductionEnv() && "mock".equals(provider)) {
    response.setStatus(HttpServletResponse.SC_SERVICE_UNAVAILABLE);
    out.print(GSON.toJson(Map.of("error", "Mock gateway is disabled in production", "code", "GATEWAY_MISCONFIGURED")));
    return;
  }

  String fingerprint = bookingId + "|" + userId + "|" + amountMinor + "|" + currency;
  long now = System.currentTimeMillis();

  Map<String, Object> order;
  Object checkoutParams;
  int httpStatus;

  synchronized (application) {
    Map<String, Object> existing = repoFindIdempotency(application, idempotencyKey);
    if (existing != null) {
      if (!fingerprint.equals(existing.get("fingerprint"))) {
        response.setStatus(HttpServletResponse.SC_CONFLICT);
        out.print(GSON.toJson(Map.of("error", "Idempotency-Key reused with different request parameters")));
        return;
      }
      order = (Map<String, Object>) existing.get("order");
      checkoutParams = existing.get("checkoutParams");
      httpStatus = HttpServletResponse.SC_OK;
    } else {
      String suffix = UUID.randomUUID().toString().replace("-", "").substring(0, 12);
      String paymentOrderId = "po_" + suffix;

      Map<String, Object> gwRes = createGatewayOrder(provider, paymentOrderId, bookingId, userId, amountMinor, currency);
      if (!Boolean.TRUE.equals(gwRes.get("ok"))) {
        response.setStatus(((Number) gwRes.get("httpStatus")).intValue());
        out.print(GSON.toJson(Map.of("error", gwRes.get("message"), "code", gwRes.get("code"))));
        return;
      }

      String providerOrderId = String.valueOf(gwRes.get("providerOrderId"));
      order = new ConcurrentHashMap<String, Object>();
      order.put("paymentOrderId", paymentOrderId);
      order.put("providerOrderId", providerOrderId);
      order.put("provider", provider);
      order.put("bookingId", bookingId);
      order.put("userId", userId);
      order.put("amountMinor", amountMinor);
      order.put("currency", currency);
      order.put("status", gwRes.get("status"));
      order.put("createdAt", Instant.now().toString());

      checkoutParams = gwRes.get("checkoutParams");
      repoSaveNewOrder(application, idempotencyKey, fingerprint, order, checkoutParams, now + IDEMPOTENCY_TTL_MS);
      httpStatus = HttpServletResponse.SC_CREATED;
    }
  }

  Map<String, Object> dto = new LinkedHashMap<String, Object>();
  dto.put("paymentOrderId", order.get("paymentOrderId"));
  dto.put("providerOrderId", order.get("providerOrderId"));
  dto.put("status", order.get("status"));
  dto.put("amountMinor", order.get("amountMinor"));
  dto.put("currency", order.get("currency"));
  if (checkoutParams != null) {
    dto.put("checkoutParams", checkoutParams);
  }
  response.setStatus(httpStatus);
  out.print(GSON.toJson(dto));
%>
