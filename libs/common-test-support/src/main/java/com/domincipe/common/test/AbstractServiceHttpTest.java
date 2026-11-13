package com.domincipe.common.test;

import com.jayway.jsonpath.JsonPath;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;
import org.springframework.boot.test.web.server.LocalServerPort;

/**
 * HTTP plumbing shared by the service contracts.
 *
 * <p>The contracts talk to the service on its random port instead of slicing the MVC layer,
 * because the guarantees of the service-runtime spec are about the running process: Actuator
 * exposure comes from the shared auto-configuration, the correlation filter is a servlet filter
 * and the Prometheus endpoint is contributed by the registry. A slice test would mock away exactly
 * what has to be proven.
 */
public abstract class AbstractServiceHttpTest {

    private static final HttpClient HTTP_CLIENT = HttpClient.newHttpClient();

    /**
     * Swagger UI answers with a redirect to its index, so this client follows it: the spec asks
     * for the page the client ends up on, not for the hop.
     */
    private static final HttpClient REDIRECTING_HTTP_CLIENT = HttpClient.newBuilder()
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    @LocalServerPort
    private int port;

    /**
     * Sends a GET to the service under test.
     *
     * @param path absolute path of the endpoint, query string included
     * @return the response, whatever its status code
     * @throws IOException when the request cannot be sent
     * @throws InterruptedException when the calling thread is interrupted while waiting
     */
    protected final HttpResponse<String> get(final String path) throws IOException, InterruptedException {
        return send(HTTP_CLIENT, path, Map.of());
    }

    /**
     * Sends a GET with extra headers to the service under test.
     *
     * @param path absolute path of the endpoint, query string included
     * @param headers headers added to the request
     * @return the response, whatever its status code
     * @throws IOException when the request cannot be sent
     * @throws InterruptedException when the calling thread is interrupted while waiting
     */
    protected final HttpResponse<String> get(final String path, final Map<String, String> headers)
            throws IOException, InterruptedException {
        return send(HTTP_CLIENT, path, headers);
    }

    /**
     * Sends a GET following redirects.
     *
     * @param path absolute path of the endpoint, query string included
     * @return the response of the last hop, whatever its status code
     * @throws IOException when the request cannot be sent
     * @throws InterruptedException when the calling thread is interrupted while waiting
     */
    protected final HttpResponse<String> getFollowingRedirects(final String path)
            throws IOException, InterruptedException {
        return send(REDIRECTING_HTTP_CLIENT, path, Map.of());
    }

    /**
     * Sends a GET with the given client.
     *
     * @param client client that decides whether redirects are followed
     * @param path absolute path of the endpoint
     * @param headers headers added to the request
     * @return the response, whatever its status code
     * @throws IOException when the request cannot be sent
     * @throws InterruptedException when the calling thread is interrupted while waiting
     */
    private HttpResponse<String> send(final HttpClient client, final String path,
            final Map<String, String> headers) throws IOException, InterruptedException {
        URI uri = URI.create("http://localhost:" + port + path);
        HttpRequest.Builder request = HttpRequest.newBuilder(uri).GET();
        headers.forEach(request::header);
        return client.send(request.build(), HttpResponse.BodyHandlers.ofString());
    }

    /**
     * Reads a field of a JSON document returned by the service.
     *
     * <p>json-path is part of {@code spring-boot-starter-test}, so the contract does not have to
     * add a JSON stack of its own just to read {@code $.status} or {@code $.info.title}.
     *
     * @param body JSON returned by the service
     * @param path json-path expression of the field to read
     * @return the field value as text
     */
    protected static String textAt(final String body, final String path) {
        return JsonPath.read(body, path);
    }
}
