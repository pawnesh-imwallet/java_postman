<%@ page isErrorPage="true" trimDirectiveWhitespaces="true" contentType="application/json;charset=UTF-8" %><%
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("X-Frame-Options", "DENY");
  response.setHeader("Cache-Control", "no-store");
  Object codeObj = request.getAttribute("jakarta.servlet.error.status_code");
  int status = (codeObj instanceof Integer) ? ((Integer) codeObj).intValue() : 500;
  if (status < 400) status = 500;
  response.setStatus(status);
  String code = (status == 404) ? "ROUTE_NOT_FOUND" : "INTERNAL_ERROR";
  String msg = (status == 404) ? "Route not found" : "Internal server error";
  out.print("{\"success\":false,\"code\":\"" + code + "\",\"message\":\"" + msg + "\"}");
%>
