// Copyright (C) The Arvados Authors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0

package org.arvados.sdk;

import java.io.File;
import java.io.FileInputStream;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.GregorianCalendar;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.junit.Test;

import static org.junit.Assert.*;

/**
 * Unit test for Arvados.
 */
public class ArvadosTest {

  /**
   * Test users.list api
   * @throws Exception
   */
  @Test
  public void testCallUsersList() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Map<String, Object> params = new HashMap<String, Object>();

    Map response = arv.call("users", "list", params);
    assertEquals("Expected kind to be users.list", "arvados#userList", response.get("kind"));

    List items = (List)response.get("items");
    assertNotNull("expected users list items", items);
    assertTrue("expected at least one item in users list", items.size()>0);

    Map firstUser = (Map)items.get(0);
    assertNotNull ("Expcted at least one user", firstUser);

    assertEquals("Expected kind to be user", "arvados#user", firstUser.get("kind"));
    assertNotNull("Expected uuid for first user", firstUser.get("uuid"));
  }

  /**
   * Test users.get <uuid> api
   * @throws Exception
   */
  @Test
  public void testCallUsersGet() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    // call user.system and get uuid of this user
    Map<String, Object> params = new HashMap<String, Object>();

    Map response = arv.call("users", "list", params);

    assertNotNull("expected users list", response);
    List items = (List)response.get("items");
    assertNotNull("expected users list items", items);

    Map firstUser = (Map)items.get(0);
    String userUuid = (String)firstUser.get("uuid");

    // invoke users.get with the system user uuid
    params = new HashMap<String, Object>();
    params.put("uuid", userUuid);

    response = arv.call("users", "get", params);

    assertNotNull("Expected uuid for first user", response.get("uuid"));
    assertEquals("Expected system user uuid", userUuid, response.get("uuid"));
  }

  /**
   * Test users.create api
   * @throws Exception
   */
  @Test
  public void testCreateUser() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Map<String, Object> params = new HashMap<String, Object>();
    params.put("user", "{}");
    Map response = arv.call("users", "create", params);

    assertEquals("Expected kind to be user", "arvados#user", response.get("kind"));

    Object uuid = response.get("uuid");
    assertNotNull("Expected uuid for first user", uuid);

    // delete the object
    params = new HashMap<String, Object>();
    params.put("uuid", uuid);
    response = arv.call("users", "delete", params);

    // invoke users.get with the system user uuid
    params = new HashMap<String, Object>();
    params.put("uuid", uuid);

    Exception caught = null;
    try {
      arv.call("users", "get", params);
    } catch (Exception e) {
      caught = e;
    }

    assertNotNull ("expected exception", caught);
    assertTrue ("Expected 404", caught.getMessage().contains("Path not found"));
  }

  @Test
  public void testCreateUserWithMissingRequiredParam() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Map<String, Object> params = new HashMap<String, Object>();

    Exception caught = null;
    try {
      arv.call("users", "create", params);
    } catch (Exception e) {
      caught = e;
    }

    assertNotNull ("expected exception", caught);
    assertTrue ("Expected POST method requires content object user",
        caught.getMessage().contains("ERROR: POST method requires content object user"));
  }

  /**
   * Test users.create api
   * @throws Exception
   */
  @Test
  public void testCreateAndUpdateUser() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Map<String, Object> params = new HashMap<String, Object>();
    params.put("user", "{}");
    Map response = arv.call("users", "create", params);

    assertEquals("Expected kind to be user", "arvados#user", response.get("kind"));

    Object uuid = response.get("uuid");
    assertNotNull("Expected uuid for first user", uuid);

    // update this user
    params = new HashMap<String, Object>();
    params.put("user", "{}");
    params.put("uuid", uuid);
    response = arv.call("users", "update", params);

    assertEquals("Expected kind to be user", "arvados#user", response.get("kind"));

    uuid = response.get("uuid");
    assertNotNull("Expected uuid for first user", uuid);

    // delete the object
    params = new HashMap<String, Object>();
    params.put("uuid", uuid);
    response = arv.call("users", "delete", params);
  }

  /**
   * Test unsupported api version api
   * @throws Exception
   */
  @Test
  public void testUnsupportedApiName() throws Exception {
    Exception caught = null;
    try {
      Arvados arv = new Arvados("not_arvados", "v1");
    } catch (Exception e) {
      caught = e;
    }

    assertNotNull ("expected exception", caught);
    assertTrue ("Expected 404 when unsupported api is used", caught.getMessage().contains("404 Not Found"));
  }

  /**
   * Test unsupported api version api
   * @throws Exception
   */
  @Test
  public void testUnsupportedVersion() throws Exception {
    Exception caught = null;
    try {
      Arvados arv = new Arvados("arvados", "v2");
    } catch (Exception e) {
      caught = e;
    }

    assertNotNull ("expected exception", caught);
    assertTrue ("Expected 404 when unsupported version is used", caught.getMessage().contains("404 Not Found"));
  }

  /**
   * Test unsupported api version api
   * @throws Exception
   */
  @Test
  public void testCallForNoSuchResrouce() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Exception caught = null;
    try {
      arv.call("abcd", "list", null);
    } catch (Exception e) {
      caught = e;
    }

    assertNotNull ("expected exception", caught);
    assertTrue ("Expected ERROR: 404 not found", caught.getMessage().contains("ERROR: resource not found"));
  }

  /**
   * Test unsupported api version api
   * @throws Exception
   */
  @Test
  public void testCallForNoSuchResrouceMethod() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Exception caught = null;
    try {
      arv.call("users", "abcd", null);
    } catch (Exception e) {
      caught = e;
    }

    assertNotNull ("expected exception", caught);
    assertTrue ("Expected ERROR: 404 not found", caught.getMessage().contains("ERROR: method not found"));
  }

  /**
   * Test pipeline_tempates.create api
   * @throws Exception
   */
  @Test
  public void testCreateAndGetPipelineTemplate() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    File file = new File(getClass().getResource( "/first_pipeline.json" ).toURI());
    byte[] data = new byte[(int)file.length()];
    try {
      FileInputStream is = new FileInputStream(file);
      is.read(data);
      is.close();
    }catch(Exception e) {
      e.printStackTrace();
    }

    Map<String, Object> params = new HashMap<String, Object>();
    params.put("pipeline_template", new String(data));
    Map response = arv.call("pipeline_templates", "create", params);
    assertEquals("Expected kind to be user", "arvados#pipelineTemplate", response.get("kind"));
    String uuid = (String)response.get("uuid");
    assertNotNull("Expected uuid for pipeline template", uuid);

    // get the pipeline
    params = new HashMap<String, Object>();
    params.put("uuid", uuid);
    response = arv.call("pipeline_templates", "get", params);

    assertEquals("Expected kind to be user", "arvados#pipelineTemplate", response.get("kind"));
    assertEquals("Expected uuid for pipeline template", uuid, response.get("uuid"));

    // delete the object
    params = new HashMap<String, Object>();
    params.put("uuid", uuid);
    response = arv.call("pipeline_templates", "delete", params);
  }

  /**
   * Test users.list api
   * @throws Exception
   */
  @Test
  public void testArvadosWithTokenPassed() throws Exception {
    String token = System.getenv().get("ARVADOS_API_TOKEN");
    String host = System.getenv().get("ARVADOS_API_HOST");
    String hostInsecure = System.getenv().get("ARVADOS_API_HOST_INSECURE");

    Arvados arv = new Arvados("arvados", "v1", token, host, hostInsecure);

    Map<String, Object> params = new HashMap<String, Object>();

    Map response = arv.call("users", "list", params);
    assertEquals("Expected kind to be users.list", "arvados#userList", response.get("kind"));
  }

  /**
   * Test users.list api
   * @throws Exception
   */
  @Test
  public void testCallUsersListWithLimit() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Map<String, Object> params = new HashMap<String, Object>();

    Map response = arv.call("users", "list", params);
    assertEquals("Expected users.list in response", "arvados#userList", response.get("kind"));

    List items = (List)response.get("items");
    assertNotNull("expected users list items", items);
    assertTrue("expected at least one item in users list", items.size()>0);

    int numUsersListItems = items.size();

    // make the request again with limit
    params = new HashMap<String, Object>();
    params.put("limit", numUsersListItems-1);

    response = arv.call("users", "list", params);

    assertEquals("Expected kind to be users.list", "arvados#userList", response.get("kind"));

    items = (List)response.get("items");
    assertNotNull("expected users list items", items);
    assertTrue("expected at least one item in users list", items.size()>0);

    int numUsersListItems2 = items.size();
    assertEquals ("Got more users than requested", numUsersListItems-1, numUsersListItems2);
  }

  @Test
  public void testGetLinksWithFilters() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Map<String, Object> params = new HashMap<String, Object>();

    Map response = arv.call("links", "list", params);
    assertEquals("Expected links.list in response", "arvados#linkList", response.get("kind"));

    String[][] filters = new String[1][];
    String[] condition = new String[3];
    condition[0] = "name";
    condition[1] = "=";
    condition[2] = "can_manage";
    filters[0] = condition;
    params.put("filters", filters);

    response = arv.call("links", "list", params);

    assertEquals("Expected links.list in response", "arvados#linkList", response.get("kind"));
    assertFalse("Expected no can_manage in response", response.toString().contains("\"name\":\"can_manage\""));
  }

  @Test
  public void testGetLinksWithFiltersAsList() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Map<String, Object> params = new HashMap<String, Object>();

    Map response = arv.call("links", "list", params);
    assertEquals("Expected links.list in response", "arvados#linkList", response.get("kind"));

    List<List> filters = new ArrayList<List>();
    List<String> condition = new ArrayList<String>();
    condition.add("name");
    condition.add("is_a");
    condition.add("can_manage");
    filters.add(condition);
    params.put("filters", filters);

    response = arv.call("links", "list", params);

    assertEquals("Expected links.list in response", "arvados#linkList", response.get("kind"));
    assertFalse("Expected no can_manage in response", response.toString().contains("\"name\":\"can_manage\""));
  }

  @Test
  public void testGetLinksWithTimestampFilters() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Map<String, Object> params = new HashMap<String, Object>();

    Map response = arv.call("links", "list", params);
    assertEquals("Expected links.list in response", "arvados#linkList", response.get("kind"));

    // get links created "tomorrow". Expect none in response
    Calendar calendar = new GregorianCalendar();
    calendar.setTime(new Date());
    calendar.add(Calendar.DAY_OF_MONTH, 1);

    Object[][] filters = new Object[1][];
    Object[] condition = new Object[3];
    condition[0] = "created_at";
    condition[1] = ">";
    condition[2] = calendar.get(Calendar.YEAR) + "-" + (calendar.get(Calendar.MONTH)+1) + "-" + calendar.get(Calendar.DAY_OF_MONTH);
    filters[0] = condition;
    params.put("filters", filters);

    response = arv.call("links", "list", params);

    assertEquals("Expected links.list in response", "arvados#linkList", response.get("kind"));
    int items_avail = ((BigDecimal)response.get("items_available")).intValue();
    assertEquals("Expected zero links", items_avail, 0);
  }

  @Test
  public void testGetLinksWithWhereClause() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");

    Map<String, Object> params = new HashMap<String, Object>();

    Map<String, String> where = new HashMap<String, String>();
    where.put("where", "updated_at > '2014-05-01'");

    params.put("where", where);

    Map response = arv.call("links", "list", params);

    assertEquals("Expected links.list in response", "arvados#linkList", response.get("kind"));
  }

  @Test
  public void testGetAvailableResources() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");
    Set<String> resources = arv.getAvailableResourses();
    assertNotNull("Expected resources", resources);
    assertTrue("Excected users in resrouces", resources.contains("users"));
  }

  @Test
  public void testGetAvailableMethodsResources() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");
    Set<String> methods = arv.getAvailableMethodsForResourse("users");
    assertNotNull("Expected resources", methods);
    assertTrue("Excected create method for users", methods.contains("create"));
  }

  @Test
  public void testGetAvailableParametersForUsersGetMethod() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");
    Map<String,List<String>> parameters = arv.getAvailableParametersForMethod("users", "get");
    assertNotNull("Expected parameters", parameters);
    assertTrue("Excected uuid parameter for get method for users", parameters.get("required").contains("uuid"));
  }

  @Test
  public void testGetAvailableParametersForUsersCreateMethod() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");
    Map<String,List<String>> parameters = arv.getAvailableParametersForMethod("users", "create");
    assertNotNull("Expected parameters", parameters);
    assertTrue("Excected user parameter for get method for users", parameters.get("required").contains("user"));
  }

  @Test
  public void testGetAvailableParametersForUsersListMethod() throws Exception {
    Arvados arv = new Arvados("arvados", "v1");
    Map<String,List<String>> parameters = arv.getAvailableParametersForMethod("users", "list");
    assertNotNull("Expected parameters", parameters);
    assertTrue("Excected no required parameter for list method for users", parameters.get("required").size() == 0);
    assertTrue("Excected some optional parameters for list method for users", parameters.get("optional").contains("filters"));
  }

}
