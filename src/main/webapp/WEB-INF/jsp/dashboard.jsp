<%@ page contentType="text/html;charset=UTF-8" language="java" %><%@ include file="/WEB-INF/jspf/common.jspf" %><%@ include file="/WEB-INF/jspf/security.jspf" %><%@ include file="/WEB-INF/jspf/db.jspf" %><%@ include file="/WEB-INF/jspf/callback.jspf" %><%
  boolean isProd = isProductionEnv();
  if (isProd) {
    applySecurityHeaders(response, false);
    response.setStatus(HttpServletResponse.SC_NOT_FOUND);
    response.setContentType("application/json;charset=UTF-8");
    out.print("{\"success\":false,\"code\":\"ROUTE_NOT_FOUND\",\"message\":\"Route not found\"}");
    return;
  }
  applySecurityHeaders(response, true);

  if ("POST".equalsIgnoreCase(request.getMethod())) {
    String poId = request.getParameter("paymentOrderId");
    String status = request.getParameter("status");
    if (poId != null && REF_ID.matcher(poId.trim()).matches()
        && ("captured".equals(status) || "failed".equals(status) || "refunded".equals(status))) {
      Map<String, Object> order = repoFindOrderById(application, poId.trim());
      if (order != null) {
        String eventId = "sim:" + poId.trim() + ":" + status + ":" + System.currentTimeMillis();
        repoRecordWebhookAndUpdate(application, eventId, "simulator", poId.trim(), status);
        order.put("status", status);
        sendNodePaymentEvent(application, order, status);
      }
    }
    response.sendRedirect(request.getContextPath() + "/dashboard");
    return;
  }

  List<Map<String, Object>> orders = new ArrayList<Map<String, Object>>(getOrdersStore(application).values());
  Collections.reverse(orders);
  List<Map<String, Object>> callbacks = getCallbackLogs(application);
  String activeGateway = activeGatewayName();
  String nodeUrl = nodeCallbackUrl();
%>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>AAITrip Java Payments (Pure JSP)</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; background: #f8fafc; color: #0f172a; }
    .card { background: #fff; border: 1px solid #e2e8f0; border-radius: 12px; padding: 20px; margin-bottom: 20px; }
    h1 { margin: 0 0 8px; font-size: 22px; }
    h2 { margin: 0 0 12px; font-size: 16px; color: #334155; }
    .meta { font-size: 13px; color: #475569; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th, td { text-align: left; padding: 10px 8px; border-bottom: 1px solid #e2e8f0; }
    th { color: #475569; font-weight: 600; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 11px; font-weight: 600; background: #e2e8f0; }
    .captured { background: #dcfce7; color: #166534; }
    .failed { background: #fee2e2; color: #991b1b; }
    .created { background: #dbeafe; color: #1e40af; }
    button { padding: 5px 10px; border-radius: 6px; border: 1px solid #cbd5e1; background: #fff; cursor: pointer; font-size: 12px; }
    button:hover { background: #f1f5f9; }
  </style>
</head>
<body>
  <div class="card">
    <h1>AAITrip Java Payments Backend (Dev Console)</h1>
    <div class="meta">
      Runtime: <strong>Pure JSP (No .java Classes, No Framework)</strong> &nbsp;|&nbsp;
      Active Gateway: <strong><%= escHtml(activeGateway) %></strong> &nbsp;|&nbsp;
      Storage: <strong><%= isDbEnabled() ? "PostgreSQL (transaction_management)" : "In-Memory (Dev)" %></strong> &nbsp;|&nbsp;
      Node Callback Target: <code><%= escHtml(nodeUrl) %></code>
    </div>
  </div>

  <div class="card">
    <h2>Payment Orders (<%= orders.size() %>)</h2>
    <table>
      <thead>
        <tr>
          <th>Payment Order ID</th>
          <th>Provider</th>
          <th>Provider Order ID</th>
          <th>Booking ID</th>
          <th>Amount (Paise)</th>
          <th>Status</th>
          <th>Created At</th>
          <th>Dev Actions (Callback to Node)</th>
        </tr>
      </thead>
      <tbody>
        <% if (orders.isEmpty()) { %>
          <tr><td colspan="8">No payment orders yet. Call <code>POST /internal/payments/orders</code> from AAITripBackendBase.</td></tr>
        <% } else {
             for (Map<String, Object> o : orders) { %>
          <tr>
            <td><code><%= escHtml(o.get("paymentOrderId")) %></code></td>
            <td><%= escHtml(o.get("provider")) %></td>
            <td><code><%= escHtml(o.get("providerOrderId")) %></code></td>
            <td><code><%= escHtml(o.get("bookingId")) %></code></td>
            <td><%= escHtml(o.get("amountMinor")) %> <%= escHtml(o.get("currency")) %></td>
            <td><span class="badge <%= escHtml(o.get("status")) %>"><%= escHtml(o.get("status")) %></span></td>
            <td><%= escHtml(o.get("createdAt")) %></td>
            <td>
              <form method="post" action="<%= escHtml(request.getContextPath()) %>/payments/simulate" style="display:inline;">
                <input type="hidden" name="paymentOrderId" value="<%= escHtml(o.get("paymentOrderId")) %>" />
                <button type="submit" name="status" value="captured">Capture</button>
                <button type="submit" name="status" value="failed">Fail</button>
              </form>
            </td>
          </tr>
        <%   }
           } %>
      </tbody>
    </table>
  </div>

  <div class="card">
    <h2>Node Callback Delivery Log</h2>
    <table>
      <thead>
        <tr>
          <th>Event ID</th>
          <th>Payment Order</th>
          <th>Booking</th>
          <th>Status</th>
          <th>HTTP Response</th>
          <th>Timestamp</th>
        </tr>
      </thead>
      <tbody>
        <% if (callbacks.isEmpty()) { %>
          <tr><td colspan="6">No callbacks sent yet.</td></tr>
        <% } else {
             for (Map<String, Object> c : callbacks) { %>
          <tr>
            <td><code><%= escHtml(c.get("eventId")) %></code></td>
            <td><code><%= escHtml(c.get("paymentOrderId")) %></code></td>
            <td><code><%= escHtml(c.get("bookingId")) %></code></td>
            <td><%= escHtml(c.get("status")) %></td>
            <td><%= escHtml(c.get("httpStatus")) %></td>
            <td><%= escHtml(c.get("timestamp")) %></td>
          </tr>
        <%   }
           } %>
      </tbody>
    </table>
  </div>
</body>
</html>
