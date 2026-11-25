<%@ page trimDirectiveWhitespaces="true" contentType="application/json;charset=UTF-8" %><%@ include file="/WEB-INF/jspf/common.jspf" %><%@ include file="/WEB-INF/jspf/security.jspf" %><%
  applySecurityHeaders(response, false);
  response.setStatus(HttpServletResponse.SC_OK);
  out.print(GSON.toJson(Map.of(
      "success", true,
      "service", "aaitrip-java-payments",
      "engine", "pure-jsp",
      "gateway", activeGatewayName()
  )));
%>
